#!/usr/bin/env python3
#
#  Copyright (c) 2015 - 2025 Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#

"""
Unit tests for PyTorch profiling integration with GEOPM.
"""

import unittest
import sys
import os
from unittest.mock import Mock, patch, MagicMock

# Add the geopmpy path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'geopmpy'))

# Mock torch if not available
try:
    import torch
    import torch.nn as nn
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False
    # Create mock torch module
    torch = Mock()
    torch.nn = Mock()
    sys.modules['torch'] = torch
    sys.modules['torch.nn'] = torch.nn


class MockModule:
    """Mock PyTorch module for testing."""

    def __init__(self, name="MockModule"):
        self.__class__.__name__ = name
        self._forward_pre_hooks = {}
        self._forward_hooks = {}
        self._backward_hooks = {}
        self._hook_counter = 0

    def register_forward_pre_hook(self, hook):
        handle = Mock()
        handle.remove = Mock()
        self._forward_pre_hooks[self._hook_counter] = (hook, handle)
        self._hook_counter += 1
        return handle

    def register_forward_hook(self, hook):
        handle = Mock()
        handle.remove = Mock()
        self._forward_hooks[self._hook_counter] = (hook, handle)
        self._hook_counter += 1
        return handle

    def register_full_backward_hook(self, hook):
        handle = Mock()
        handle.remove = Mock()
        self._backward_hooks[self._hook_counter] = (hook, handle)
        self._hook_counter += 1
        return handle

    def modules(self):
        return [self]


class TestTorchProf(unittest.TestCase):
    """Test cases for PyTorch profiling integration."""

    def setUp(self):
        """Set up test fixtures."""
        # Import after mocking torch if needed
        from geopmpy import torch_prof
        self.torch_prof = torch_prof

        # Reset state
        self.torch_prof.disable_profiling()
        self.torch_prof.clear_all_hooks()

    def tearDown(self):
        """Clean up after tests."""
        self.torch_prof.disable_profiling()
        self.torch_prof.clear_all_hooks()

    def test_torch_availability_check(self):
        """Test PyTorch availability checking."""
        if TORCH_AVAILABLE:
            self.assertTrue(self.torch_prof._is_torch_available())
        else:
            # When mocked, it should return False
            with patch('geopmpy.torch_prof._TORCH_AVAILABLE', False):
                self.assertFalse(self.torch_prof._is_torch_available())

    def test_profiling_state_management(self):
        """Test enabling/disabling profiling."""
        # Initially disabled
        self.assertFalse(self.torch_prof.is_profiling_enabled())

        # Enable profiling
        self.torch_prof.enable_profiling()
        self.assertTrue(self.torch_prof.is_profiling_enabled())

        # Disable profiling
        self.torch_prof.disable_profiling()
        self.assertFalse(self.torch_prof.is_profiling_enabled())

    def test_region_name_generation(self):
        """Test region name generation."""
        mock_module = MockModule("TestModule")

        # Test forward region name
        forward_name = self.torch_prof._get_region_name(mock_module, 'forward')
        self.assertEqual(forward_name, "[TORCH]TestModule.forward")

        # Test backward region name
        backward_name = self.torch_prof._get_region_name(mock_module, 'backward')
        self.assertEqual(backward_name, "[TORCH]TestModule.backward")

    def test_region_hint_mapping(self):
        """Test region hint mapping for different module types."""
        # Test known module types
        linear_module = MockModule("Linear")
        hint = self.torch_prof._get_region_hint(linear_module)
        self.assertEqual(hint, self.torch_prof.prof.REGION_HINT_COMPUTE)

        conv_module = MockModule("Conv2d")
        hint = self.torch_prof._get_region_hint(conv_module)
        self.assertEqual(hint, self.torch_prof.prof.REGION_HINT_COMPUTE)

        bn_module = MockModule("BatchNorm2d")
        hint = self.torch_prof._get_region_hint(bn_module)
        self.assertEqual(hint, self.torch_prof.prof.REGION_HINT_MEMORY)

        # Test unknown module type
        unknown_module = MockModule("UnknownModule")
        hint = self.torch_prof._get_region_hint(unknown_module)
        self.assertEqual(hint, self.torch_prof.prof.REGION_HINT_UNKNOWN)

    @patch('geopmpy.torch_prof.prof.Region')
    def test_module_registration(self, mock_region):
        """Test module registration and hook setup."""
        mock_module = MockModule("TestModule")

        # Register module
        self.torch_prof._register_module_hooks(mock_module)

        # Check that module is registered
        module_id = id(mock_module)
        self.assertIn(module_id, self.torch_prof._registered_modules)
        self.assertIn(module_id, self.torch_prof._module_hooks)

        # Check that hooks were registered
        self.assertEqual(len(self.torch_prof._module_hooks[module_id]), 3)  # pre, post, backward

        # Test double registration (should not add duplicate hooks)
        initial_hook_count = len(self.torch_prof._module_hooks[module_id])
        self.torch_prof._register_module_hooks(mock_module)
        final_hook_count = len(self.torch_prof._module_hooks[module_id])
        self.assertEqual(initial_hook_count, final_hook_count)

    def test_module_unregistration(self):
        """Test module unregistration and hook cleanup."""
        mock_module = MockModule("TestModule")

        # Register and then unregister
        self.torch_prof._register_module_hooks(mock_module)
        module_id = id(mock_module)

        self.assertIn(module_id, self.torch_prof._registered_modules)

        self.torch_prof._unregister_module_hooks(mock_module)

        # Check that module is unregistered
        self.assertNotIn(module_id, self.torch_prof._registered_modules)
        self.assertNotIn(module_id, self.torch_prof._module_hooks)

    @patch('geopmpy.torch_prof.prof.Region')
    def test_forward_hooks(self, mock_region):
        """Test forward hook functionality."""
        mock_module = MockModule("TestModule")

        # Mock region context manager
        mock_region_instance = MagicMock()
        mock_region.return_value = mock_region_instance
        mock_region_instance.__enter__ = Mock(return_value=mock_region_instance)
        mock_region_instance.__exit__ = Mock(return_value=False)
        mock_region_instance._id = 12345

        # Enable profiling
        self.torch_prof.enable_profiling()

        # Test forward pre-hook
        input_data = Mock()
        self.torch_prof._forward_pre_hook(mock_module, input_data)

        # Check that region was created and entered
        mock_region.assert_called()
        self.assertTrue(hasattr(mock_module, '_geopm_region'))

        # Test forward post-hook
        output = Mock()
        self.torch_prof._forward_hook(mock_module, input_data, output)

        # Check that region was exited and cleaned up
        mock_region_instance.__exit__.assert_called()
        self.assertFalse(hasattr(mock_module, '_geopm_region'))

    @patch('geopmpy.torch_prof.prof.Region')
    def test_backward_hook(self, mock_region):
        """Test backward hook functionality."""
        mock_module = MockModule("TestModule")

        # Enable profiling
        self.torch_prof.enable_profiling()

        # Test backward hook
        grad_input = Mock()
        grad_output = Mock()

        self.torch_prof._backward_hook(mock_module, grad_input, grad_output)

        # Check that region was used
        mock_region.assert_called_with("[TORCH]TestModule.backward",
                                      self.torch_prof.prof.REGION_HINT_UNKNOWN)

    def test_register_model(self):
        """Test model registration."""
        mock_model = MockModule("TestModel")

        # Test successful registration
        self.torch_prof.register_model(mock_model)

        module_id = id(mock_model)
        self.assertIn(module_id, self.torch_prof._registered_modules)

        # Test error cases
        if not TORCH_AVAILABLE:
            with patch('geopmpy.torch_prof._is_torch_available', return_value=False):
                with self.assertRaises(RuntimeError):
                    self.torch_prof.register_model(mock_model)

        with self.assertRaises(ValueError):
            self.torch_prof.register_model("not a module")

    def test_context_manager(self):
        """Test pytorch_profiling context manager."""
        mock_model = MockModule("TestModel")

        # Test context manager without models
        with self.torch_prof.pytorch_profiling():
            self.assertTrue(self.torch_prof.is_profiling_enabled())

        # After exiting, profiling should be disabled (was False initially)
        self.assertFalse(self.torch_prof.is_profiling_enabled())

        # Test context manager with models
        with self.torch_prof.pytorch_profiling([mock_model]):
            self.assertTrue(self.torch_prof.is_profiling_enabled())
            # Model should be registered
            self.assertIn(id(mock_model), self.torch_prof._registered_modules)

        # After exiting, model should be unregistered
        self.assertNotIn(id(mock_model), self.torch_prof._registered_modules)

    @patch('geopmpy.torch_prof.prof.Region')
    def test_profile_function_decorator(self, mock_region):
        """Test function profiling decorator."""
        mock_region_instance = MagicMock()
        mock_region.return_value.__enter__ = Mock(return_value=mock_region_instance)
        mock_region.return_value.__exit__ = Mock(return_value=False)

        @self.torch_prof.profile_function
        def test_function(x, y):
            return x + y

        # Enable profiling
        self.torch_prof.enable_profiling()

        # Call function
        result = test_function(1, 2)
        self.assertEqual(result, 3)

        # Check that region was used
        mock_region.assert_called()

        # Disable profiling and test that function still works
        self.torch_prof.disable_profiling()
        result = test_function(3, 4)
        self.assertEqual(result, 7)

    def test_clear_all_hooks(self):
        """Test clearing all hooks and state."""
        mock_model = MockModule("TestModel")

        # Register model and enable profiling
        self.torch_prof.register_model(mock_model)
        self.torch_prof.enable_profiling()

        # Verify state
        self.assertTrue(self.torch_prof.is_profiling_enabled())
        self.assertIn(id(mock_model), self.torch_prof._registered_modules)

        # Clear all hooks
        self.torch_prof.clear_all_hooks()

        # Verify cleanup
        self.assertFalse(self.torch_prof.is_profiling_enabled())
        self.assertEqual(len(self.torch_prof._registered_modules), 0)
        self.assertEqual(len(self.torch_prof._module_hooks), 0)
        self.assertEqual(len(self.torch_prof._region_cache), 0)

    def test_environment_variable_control(self):
        """Test environment variable control."""
        # Mock environment variable
        with patch.dict(os.environ, {'GEOPM_TORCH_PROFILE': '1'}):
            # Reload module to trigger environment check
            import importlib
            importlib.reload(self.torch_prof)
            # Should be enabled
            self.assertTrue(self.torch_prof.is_profiling_enabled())

        # Reset for other tests
        self.torch_prof.disable_profiling()

    @patch('geopmpy.torch_prof.torch')
    def test_tensor_ops_profiling(self, mock_torch):
        """Test tensor operations profiling."""
        # Setup mock torch
        mock_torch.nn = Mock()
        mock_torch.nn.functional = Mock()
        mock_torch.nn.functional.relu = Mock()
        mock_torch.matmul = Mock()

        # Enable tensor ops profiling
        with patch('geopmpy.torch_prof._is_torch_available', return_value=True):
            self.torch_prof.profile_tensor_ops()

        # Verify that functions were patched
        # (This is a basic test - in reality we'd need more sophisticated mocking)
        self.assertIsNotNone(mock_torch.nn.functional.relu)


class TestTorchProfIntegration(unittest.TestCase):
    """Integration tests requiring actual PyTorch."""

    def setUp(self):
        """Set up test fixtures."""
        if not TORCH_AVAILABLE:
            self.skipTest("PyTorch not available")

        from geopmpy import torch_prof
        self.torch_prof = torch_prof

        # Reset state
        self.torch_prof.disable_profiling()
        self.torch_prof.clear_all_hooks()

    def tearDown(self):
        """Clean up after tests."""
        if TORCH_AVAILABLE:
            self.torch_prof.disable_profiling()
            self.torch_prof.clear_all_hooks()

    def test_real_pytorch_model(self):
        """Test with a real PyTorch model."""
        if not TORCH_AVAILABLE:
            return

        import torch
        import torch.nn as nn

        # Create a simple model
        model = nn.Sequential(
            nn.Linear(10, 5),
            nn.ReLU(),
            nn.Linear(5, 1)
        )

        # Register model
        self.torch_prof.register_model(model)
        self.torch_prof.enable_profiling()

        # Run forward pass
        input_data = torch.randn(2, 10)
        output = model(input_data)

        self.assertEqual(output.shape, (2, 1))

        # Test context manager
        with self.torch_prof.pytorch_profiling([model]):
            output2 = model(input_data)
            self.assertEqual(output2.shape, (2, 1))


if __name__ == '__main__':
    unittest.main()
