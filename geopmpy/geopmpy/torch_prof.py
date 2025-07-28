#
#  Copyright (c) 2015 - 2025 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#

"""
PyTorch Profiling Integration for GEOPM

This module provides automatic profiling of PyTorch operations using GEOPM's
profiling interfaces. It integrates with PyTorch's hook system to automatically
track model operations as regions.

Usage:
    import torch
    from geopmdpy import torch_prof

    # Enable PyTorch profiling
    torch_prof.enable_profiling()

    # Your PyTorch code
    model = torch.nn.Linear(10, 5)
    x = torch.randn(32, 10)
    y = model(x)

    # Disable profiling
    torch_prof.disable_profiling()

Or use as context manager:
    with torch_prof.pytorch_profiling():
        # Your PyTorch code
        y = model(x)
"""

import os
import sys
import weakref
from functools import wraps
from collections import defaultdict
from typing import Dict, Set, Optional, Any, Callable, List

try:
    import torch
    import torch.nn as nn
    _TORCH_AVAILABLE = True
except ImportError:
    _TORCH_AVAILABLE = False

from . import prof
from . import error

# Global state for PyTorch profiling
_profiling_enabled = False
_registered_modules: Set[int] = set()  # Track registered module IDs
_module_hooks: Dict[int, List] = defaultdict(list)  # Store hook handles per module
_region_cache: Dict[str, int] = {}  # Cache region IDs
_hook_counter = 0

# PyTorch operation categories and their hints
_TORCH_OPERATION_HINTS = {
    # Neural network layers
    'Linear': prof.REGION_HINT_COMPUTE,
    'Conv1d': prof.REGION_HINT_COMPUTE,
    'Conv2d': prof.REGION_HINT_COMPUTE,
    'Conv3d': prof.REGION_HINT_COMPUTE,
    'ConvTranspose1d': prof.REGION_HINT_COMPUTE,
    'ConvTranspose2d': prof.REGION_HINT_COMPUTE,
    'ConvTranspose3d': prof.REGION_HINT_COMPUTE,
    'BatchNorm1d': prof.REGION_HINT_MEMORY,
    'BatchNorm2d': prof.REGION_HINT_MEMORY,
    'BatchNorm3d': prof.REGION_HINT_MEMORY,
    'LayerNorm': prof.REGION_HINT_MEMORY,
    'GroupNorm': prof.REGION_HINT_MEMORY,
    'InstanceNorm1d': prof.REGION_HINT_MEMORY,
    'InstanceNorm2d': prof.REGION_HINT_MEMORY,
    'InstanceNorm3d': prof.REGION_HINT_MEMORY,

    # Activation functions
    'ReLU': prof.REGION_HINT_COMPUTE,
    'GELU': prof.REGION_HINT_COMPUTE,
    'Sigmoid': prof.REGION_HINT_COMPUTE,
    'Tanh': prof.REGION_HINT_COMPUTE,
    'Softmax': prof.REGION_HINT_COMPUTE,
    'LogSoftmax': prof.REGION_HINT_COMPUTE,

    # Pooling layers
    'MaxPool1d': prof.REGION_HINT_MEMORY,
    'MaxPool2d': prof.REGION_HINT_MEMORY,
    'MaxPool3d': prof.REGION_HINT_MEMORY,
    'AvgPool1d': prof.REGION_HINT_MEMORY,
    'AvgPool2d': prof.REGION_HINT_MEMORY,
    'AvgPool3d': prof.REGION_HINT_MEMORY,
    'AdaptiveAvgPool1d': prof.REGION_HINT_MEMORY,
    'AdaptiveAvgPool2d': prof.REGION_HINT_MEMORY,
    'AdaptiveAvgPool3d': prof.REGION_HINT_MEMORY,

    # Dropout and regularization
    'Dropout': prof.REGION_HINT_MEMORY,
    'Dropout2d': prof.REGION_HINT_MEMORY,
    'Dropout3d': prof.REGION_HINT_MEMORY,

    # Loss functions
    'MSELoss': prof.REGION_HINT_COMPUTE,
    'CrossEntropyLoss': prof.REGION_HINT_COMPUTE,
    'BCELoss': prof.REGION_HINT_COMPUTE,
    'BCEWithLogitsLoss': prof.REGION_HINT_COMPUTE,
    'NLLLoss': prof.REGION_HINT_COMPUTE,

    # Attention mechanisms
    'MultiheadAttention': prof.REGION_HINT_COMPUTE,

    # Default for unknown operations
    'default': prof.REGION_HINT_UNKNOWN
}


def _is_torch_available():
    """Check if PyTorch is available."""
    return _TORCH_AVAILABLE


def _get_region_name(module: 'torch.nn.Module', operation: str = 'forward') -> str:
    """Generate a region name for a PyTorch module.

    Args:
        module: PyTorch module
        operation: Operation being performed ('forward', 'backward')

    Returns:
        String region name in format '[TORCH]ModuleName.operation'
    """
    module_name = module.__class__.__name__
    return f"[TORCH]{module_name}.{operation}"


def _get_region_hint(module: 'torch.nn.Module') -> int:
    """Get the appropriate region hint for a PyTorch module.

    Args:
        module: PyTorch module

    Returns:
        GEOPM region hint constant
    """
    module_name = module.__class__.__name__
    return _TORCH_OPERATION_HINTS.get(module_name, _TORCH_OPERATION_HINTS['default'])


def _register_region(region_name: str, hint: int):
    """Register a region with GEOPM and cache the ID.

    Args:
        region_name: Name of the region
        hint: Region hint

    Returns:
        Region ID, or None if registration failed
    """
    if region_name in _region_cache:
        return _region_cache[region_name]

    try:
        with prof.Region(region_name, hint) as region:
            _region_cache[region_name] = region._id
            return region._id
    except Exception as e:
        # If profiling fails, silently continue
        return None


def _forward_pre_hook(module: 'torch.nn.Module', input_data) -> None:
    """Forward pre-hook to mark region entry.

    Args:
        module: PyTorch module
        input_data: Input data to the module
    """
    if not _profiling_enabled:
        return

    region_name = _get_region_name(module, 'forward')
    hint = _get_region_hint(module)

    try:
        # Register and enter region
        region_id = _register_region(region_name, hint)
        if region_id is not None:
            # Store region context in module for cleanup in post-hook
            module._geopm_region_name = region_name
            module._geopm_region = prof.Region(region_name, hint)
            module._geopm_region.__enter__()
    except Exception:
        # Silently continue if profiling fails
        pass


def _forward_hook(module: 'torch.nn.Module', input_data, output) -> None:
    """Forward hook to mark region exit.

    Args:
        module: PyTorch module
        input_data: Input data to the module
        output: Output from the module
    """
    if not _profiling_enabled:
        return

    try:
        # Exit region if it was entered
        if hasattr(module, '_geopm_region'):
            module._geopm_region.__exit__(None, None, None)
            delattr(module, '_geopm_region')
            delattr(module, '_geopm_region_name')
    except Exception:
        # Silently continue if profiling fails
        pass


def _backward_hook(module: 'torch.nn.Module', grad_input, grad_output) -> None:
    """Backward hook to profile gradient computation.

    Args:
        module: PyTorch module
        grad_input: Gradients with respect to inputs
        grad_output: Gradients with respect to outputs
    """
    if not _profiling_enabled:
        return

    region_name = _get_region_name(module, 'backward')
    hint = _get_region_hint(module)

    try:
        # Use region as context manager for backward pass
        with prof.Region(region_name, hint):
            pass  # The actual backward computation is done by PyTorch
    except Exception:
        # Silently continue if profiling fails
        pass


def _register_module_hooks(module: 'torch.nn.Module') -> None:
    """Register profiling hooks on a PyTorch module.

    Args:
        module: PyTorch module to register hooks on
    """
    module_id = id(module)

    if module_id in _registered_modules:
        return

    try:
        # Register forward hooks
        pre_hook = module.register_forward_pre_hook(_forward_pre_hook)
        post_hook = module.register_forward_hook(_forward_hook)
        backward_hook = module.register_full_backward_hook(_backward_hook)

        # Store hooks for cleanup
        _module_hooks[module_id].extend([pre_hook, post_hook, backward_hook])
        _registered_modules.add(module_id)

    except Exception:
        # If hook registration fails, silently continue
        pass


def _unregister_module_hooks(module: 'torch.nn.Module') -> None:
    """Unregister profiling hooks from a PyTorch module.

    Args:
        module: PyTorch module to unregister hooks from
    """
    module_id = id(module)

    if module_id not in _registered_modules:
        return

    try:
        # Remove all hooks for this module
        for hook in _module_hooks[module_id]:
            hook.remove()

        del _module_hooks[module_id]
        _registered_modules.discard(module_id)

    except Exception:
        # If hook removal fails, silently continue
        pass


def register_model(model: 'torch.nn.Module') -> None:
    """Register profiling hooks on a PyTorch model and all its submodules.

    Args:
        model: PyTorch model to register for profiling

    Raises:
        RuntimeError: If PyTorch is not available
    """
    if not _is_torch_available():
        raise RuntimeError("PyTorch is not available. Please install PyTorch to use torch_prof.")

    if not isinstance(model, torch.nn.Module):
        raise ValueError("model must be a torch.nn.Module instance")

    # Register hooks on the model and all submodules
    for module in model.modules():
        _register_module_hooks(module)


def unregister_model(model: 'torch.nn.Module') -> None:
    """Unregister profiling hooks from a PyTorch model and all its submodules.

    Args:
        model: PyTorch model to unregister from profiling

    Raises:
        RuntimeError: If PyTorch is not available
    """
    if not _is_torch_available():
        raise RuntimeError("PyTorch is not available. Please install PyTorch to use torch_prof.")

    if not isinstance(model, torch.nn.Module):
        raise ValueError("model must be a torch.nn.Module instance")

    # Unregister hooks from the model and all submodules
    for module in model.modules():
        _unregister_module_hooks(module)


def enable_profiling() -> None:
    """Enable PyTorch profiling globally.

    This will activate profiling for all registered models.
    """
    global _profiling_enabled
    _profiling_enabled = True


def disable_profiling() -> None:
    """Disable PyTorch profiling globally.

    This will deactivate profiling but keep hooks registered.
    """
    global _profiling_enabled
    _profiling_enabled = False


def is_profiling_enabled() -> bool:
    """Check if PyTorch profiling is currently enabled.

    Returns:
        True if profiling is enabled, False otherwise
    """
    return _profiling_enabled


def clear_all_hooks() -> None:
    """Remove all registered hooks and clear state.

    This is useful for cleanup when profiling is no longer needed.
    """
    global _profiling_enabled, _registered_modules, _module_hooks, _region_cache

    if not _is_torch_available():
        return

    # Remove all hooks
    for module_id in list(_registered_modules):
        try:
            for hook in _module_hooks[module_id]:
                hook.remove()
        except Exception:
            pass

    # Clear state
    _profiling_enabled = False
    _registered_modules.clear()
    _module_hooks.clear()
    _region_cache.clear()


class pytorch_profiling:
    """Context manager for PyTorch profiling.

    Example:
        with pytorch_profiling():
            # Your PyTorch code
            output = model(input_data)
            loss = criterion(output, target)
            loss.backward()
    """

    def __init__(self, models: Optional[List['torch.nn.Module']] = None):
        """Initialize the context manager.

        Args:
            models: Optional list of models to register. If None, assumes
                   models are already registered.
        """
        self.models = models or []
        self.was_enabled = False
        self.registered_models = []

    def __enter__(self):
        """Enter the profiling context."""
        if not _is_torch_available():
            raise RuntimeError("PyTorch is not available. Please install PyTorch to use torch_prof.")

        self.was_enabled = is_profiling_enabled()

        # Register models if provided
        for model in self.models:
            register_model(model)
            self.registered_models.append(model)

        # Enable profiling
        enable_profiling()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Exit the profiling context."""
        # Restore previous profiling state
        if self.was_enabled:
            enable_profiling()
        else:
            disable_profiling()

        # Unregister models that we registered
        for model in self.registered_models:
            unregister_model(model)


def profile_function(func: Callable, region_name: Optional[str] = None,
                    hint: int = prof.REGION_HINT_COMPUTE) -> Callable:
    """Decorator to profile a function with GEOPM.

    Args:
        func: Function to profile
        region_name: Optional custom region name. If None, uses function name.
        hint: Region hint for the operation

    Returns:
        Decorated function

    Example:
        @profile_function
        def my_torch_function(x, y):
            return torch.matmul(x, y)
    """
    if region_name is None:
        region_name = f"[TORCH]Function.{func.__name__}"

    @wraps(func)
    def wrapper(*args, **kwargs):
        if _profiling_enabled:
            try:
                with prof.Region(region_name, hint):
                    return func(*args, **kwargs)
            except Exception:
                # If profiling fails, just run the function
                return func(*args, **kwargs)
        else:
            return func(*args, **kwargs)

    return wrapper


# Environment variable control
def _check_environment():
    """Check environment variables for automatic profiling setup."""
    if os.environ.get('GEOPM_TORCH_PROFILE', '').lower() in ('1', 'true', 'yes', 'on'):
        enable_profiling()


# Auto-enable profiling if environment variable is set
_check_environment()


# PyTorch tensor operation profiling
def profile_tensor_ops():
    """Enable profiling of tensor operations by monkey-patching torch functions.

    This is experimental and may have performance overhead.
    """
    if not _is_torch_available():
        raise RuntimeError("PyTorch is not available.")

    # List of common tensor operations to profile
    tensor_ops = [
        'matmul', 'bmm', 'mm', 'addmm', 'baddbmm',
        'conv1d', 'conv2d', 'conv3d', 'conv_transpose1d', 'conv_transpose2d', 'conv_transpose3d',
        'batch_norm', 'layer_norm', 'group_norm', 'instance_norm',
        'relu', 'gelu', 'sigmoid', 'tanh', 'softmax', 'log_softmax',
        'max_pool1d', 'max_pool2d', 'max_pool3d', 'avg_pool1d', 'avg_pool2d', 'avg_pool3d',
        'dropout', 'embedding', 'linear'
    ]

    # Store original functions
    _original_functions = {}

    def create_profiled_function(op_name, original_func):
        @wraps(original_func)
        def profiled_func(*args, **kwargs):
            if _profiling_enabled:
                region_name = f"[TORCH]TensorOp.{op_name}"
                hint = prof.REGION_HINT_COMPUTE
                try:
                    with prof.Region(region_name, hint):
                        return original_func(*args, **kwargs)
                except Exception:
                    return original_func(*args, **kwargs)
            else:
                return original_func(*args, **kwargs)
        return profiled_func

    # Patch torch.nn.functional operations
    if hasattr(torch, 'nn') and hasattr(torch.nn, 'functional'):
        for op_name in tensor_ops:
            if hasattr(torch.nn.functional, op_name):
                original_func = getattr(torch.nn.functional, op_name)
                _original_functions[f'torch.nn.functional.{op_name}'] = original_func
                profiled_func = create_profiled_function(op_name, original_func)
                setattr(torch.nn.functional, op_name, profiled_func)

    # Patch torch operations
    torch_ops = ['matmul', 'bmm', 'mm', 'addmm', 'baddbmm']
    for op_name in torch_ops:
        if hasattr(torch, op_name):
            original_func = getattr(torch, op_name)
            _original_functions[f'torch.{op_name}'] = original_func
            profiled_func = create_profiled_function(op_name, original_func)
            setattr(torch, op_name, profiled_func)
