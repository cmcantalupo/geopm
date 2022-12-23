#!/usr/bin/env python3
#
#  Copyright (c) 2015 - 2022, Intel Corporation
#  SPDX-License-Identifier: BSD-3-Clause
#

import os
import unittest
import re
from unittest import mock
import tempfile
with mock.patch('cffi.FFI.dlopen', return_value=mock.MagicMock()):
    from geopmdpy.system_files import ActiveSessions, AccessLists, WriteLock

# Patch dlopen to allow the tests to run when there is no build
with mock.patch('cffi.FFI.dlopen', return_value=mock.MagicMock()):
    from geopmdpy.service import PlatformService
    from geopmdpy.service import TopoService
from geopmdpy.client_registry import ClientRegistry

class TestPlatformService(unittest.TestCase):
    def setUp(self):
        self._test_name = 'TestPlatformService'
        self._RUN_PATH = tempfile.TemporaryDirectory('{}_run'.format(self._test_name))
        self._watch_id = 888
        self._client_sid = [333, 999]

        self._mock_active_sessions = mock.create_autospec(ActiveSessions)
        self._mock_active_sessions.get_clients.return_value = []
        self._check_client_active_err_msg = "Injected error"
        self._mock_active_sessions.check_client_active.side_effect = \
            RuntimeError(self._check_client_active_err_msg) # Until open_mock_session is called

        self._mock_access_lists = mock.create_autospec(AccessLists)
        self._mock_write_lock = mock.create_autospec(WriteLock)
        self._mock_client_registry = mock.create_autospec(ClientRegistry)
        self._mock_client_registry.get_groups.return_value = []
        self._mock_client_registry.watch.return_value = self._watch_id
        self._mock_client_registry.get_user.return_value = 'user_name'
        self._mock_client_registry.get_write_client.side_effect = self._client_sid

        self._mock_write_lock.try_lock.return_value = None
        self._mock_write_lock.unlock.return_value = None

        with mock.patch('geopmdpy.system_files.ActiveSessions', return_value=self._mock_active_sessions), \
             mock.patch('geopmdpy.system_files.AccessLists', return_value=self._mock_access_lists), \
             mock.patch('geopmdpy.client_registry.create_registry', return_value=self._mock_client_registry), \
             mock.patch('geopmdpy.system_files.WriteLock', return_value=self._mock_write_lock):
            self._platform_service = PlatformService()

        self._platform_service._RUN_PATH = self._RUN_PATH.name
        self._platform_service._active_sessions._RUN_PATH = self._RUN_PATH.name
        self._session_file_format = os.path.join(self._RUN_PATH.name, 'session-{client_pid}.json')

    def tearDown(self):
        self._RUN_PATH.cleanup()

    def test_close_already_closed(self):
        # We already have two independent components with the session.
        client_pid = -999
        self.open_mock_session('user_name', client_pid, True, 2)  # 2
        self._platform_service.close_session(client_pid)              # 1
        self._platform_service.close_session(client_pid)              # 0
        self._platform_service._active_sessions.check_client_active = mock.MagicMock(side_effect=RuntimeError)
        with self.assertRaises(RuntimeError):
            self._platform_service.close_session(client_pid) # error here

    def test_read_already_closed(self):
        # We already have two independent components with the session.
        client_pid = -999
        self.open_mock_session('user_name', client_pid, True, 2)  # 2
        self._platform_service.close_session(client_pid)              # 1
        self._platform_service.close_session(client_pid)              # 0
        self._platform_service._active_sessions.check_client_active = mock.MagicMock(side_effect=RuntimeError)
        with self.assertRaises(RuntimeError):
            self._platform_service.read_signal(client_pid, 'CPU_FREQUENCY', 0, 0) # error here

    def test_get_signal_info(self):
        signals = ['energy', 'frequency', 'power']
        descriptions = ['desc0', 'desc1', 'desc2']
        domains = [0, 1, 2]
        infos = [(0, 0, 0), (1, 1, 1), (2, 2, 2)]

        expected_result = list(zip(signals, descriptions, domains))
        for idx in range(len(expected_result)):
            expected_result[idx] = expected_result[idx] + infos[idx]

        with mock.patch('geopmdpy.pio.signal_description', side_effect=descriptions) as mock_desc, \
             mock.patch('geopmdpy.pio.signal_domain_type', side_effect=domains) as mock_dom, \
             mock.patch('geopmdpy.pio.signal_info', side_effect=infos) as mock_inf:

            signal_info = self._platform_service.get_signal_info(signals)
            self.assertEqual(expected_result, signal_info)

            calls = [mock.call(cc) for cc in signals]
            mock_desc.assert_has_calls(calls)
            mock_dom.assert_has_calls(calls)
            mock_inf.assert_has_calls(calls)

    def test_get_control_info(self):
        controls = ['fan', 'frequency', 'power']
        descriptions = ['desc0', 'desc1', 'desc2']
        domains = [0, 1, 2]
        expected_result = list(zip(controls, descriptions, domains))

        with mock.patch('geopmdpy.pio.control_description', side_effect=descriptions) as mock_desc, \
             mock.patch('geopmdpy.pio.control_domain_type', side_effect=domains) as mock_dom:

            control_info = self._platform_service.get_control_info(controls)
            self.assertEqual(expected_result, control_info)

            calls = [mock.call(cc) for cc in controls]
            mock_desc.assert_has_calls(calls)
            mock_dom.assert_has_calls(calls)

    def test_lock_control(self):
        err_msg = 'PlatformService: Implementation incomplete'
        with self.assertRaisesRegex(NotImplementedError, err_msg):
            self._platform_service.lock_control()

    def test_unlock_control(self):
        err_msg = 'PlatformService: Implementation incomplete'
        with self.assertRaisesRegex(NotImplementedError, err_msg):
            self._platform_service.unlock_control()

    def test_open_session_twice(self):
        self.open_mock_session('', active=True)

    def _gen_session_data_helper(self, client_pid, reference_count):
        signals_default = ['energy', 'frequency']
        controls_default = ['controls', 'geopm', 'named', 'power']

        session_data = {'client_pid': client_pid,
                        'reference_count': reference_count,
                        'mode': 'r',
                        'signals': signals_default,
                        'controls': controls_default,
                        'watch_id': self._watch_id}
        return session_data

    def open_mock_session(self, session_user, client_pid=-999, active=False, reference_count=1):

        session_data = self._gen_session_data_helper(client_pid, reference_count)
        client_pid = session_data['client_pid']
        reference_count = session_data['reference_count']
        watch_id = session_data['watch_id']
        signals = session_data['signals']
        controls = session_data['controls']

        self._mock_active_sessions.is_client_active.return_value = active
        self._mock_active_sessions.get_controls.return_value = controls
        self._mock_active_sessions.get_signals.return_value = signals
        self._mock_active_sessions.get_reference_count.return_value = reference_count
        self._mock_active_sessions.get_watch_id.return_value = watch_id
        self._mock_active_sessions.get_batch_server.return_value = None
        self._mock_active_sessions.remove_client.return_value = session_data

        self._mock_access_lists.get_user_access.return_value = (signals, controls)

        self._platform_service.open_session(session_user, client_pid)

        self._mock_active_sessions.is_client_active.assert_called_with(client_pid)
        if not active:
            self._mock_active_sessions.add_client.assert_called_with(client_pid, signals, controls, watch_id)
            self._mock_access_lists.get_user_access.assert_called_with(session_user, [])
        else:
            self._mock_active_sessions.add_client.assert_not_called()

        self._mock_active_sessions.check_client_active.side_effect = None # session is now active

        return session_data

    def test_open_session(self):
        self.open_mock_session('')

    def test_close_session_invalid(self):
        client_pid = 999
        with self.assertRaisesRegex(RuntimeError, self._check_client_active_err_msg):
            self._platform_service.close_session(client_pid)

    def test_close_session_read(self):
        session_data = self.open_mock_session('')
        client_pid = session_data['client_pid']
        watch_id = session_data['watch_id']

        with mock.patch('gi.repository.GLib.source_remove', return_value=[]) as mock_source_remove, \
             mock.patch('geopmdpy.pio.restore_control_dir') as mock_restore_control_dir, \
             mock.patch('shutil.rmtree', return_value=[]) as mock_rmtree:

            self._platform_service.close_session(client_pid)
            mock_restore_control_dir.assert_not_called()
            mock_rmtree.assert_not_called()
            self._mock_client_registry.unwatch.assert_called_once()
            self._mock_active_sessions.remove_client.assert_called_once_with(client_pid)

    def test_close_session_write(self):
        session_data = self.open_mock_session('')
        client_pid = session_data['client_pid']
        watch_id = session_data['watch_id']
        self._mock_write_lock.try_lock.return_value = client_pid
        with mock.patch('geopmdpy.pio.save_control_dir') as mock_save_control_dir, \
             mock.patch('geopmdpy.pio.write_control') as mock_write_control, \
             mock.patch('os.getsid', return_value=client_pid) as mock_getsid:
            self._platform_service.write_control(client_pid, 'geopm', 'board', 0, 42.024)
            mock_save_control_dir.assert_called_once()
            mock_write_control.assert_called_once_with('geopm', 'board', 0, 42.024)

        with mock.patch('gi.repository.GLib.source_remove', return_value=[]) as mock_source_remove, \
             mock.patch('geopmdpy.pio.restore_control_dir', return_value=[]) as mock_restore_control_dir, \
             mock.patch('os.getsid', return_value=client_pid) as mock_getsid:
            self._platform_service.close_session(client_pid)
            mock_restore_control_dir.assert_called_once()
            save_dir = os.path.join(self._platform_service._RUN_PATH,
                                    self._platform_service._SAVE_DIR)
            mock_source_remove.assert_called_once_with(watch_id)
            self.assertFalse(self._platform_service._active_sessions.is_client_active(client_pid))
            session_file = self._session_file_format.format(client_pid=client_pid)
            self.assertFalse(os.path.exists(session_file))

    def test_start_batch_invalid(self):
        session_data = self.open_mock_session('')
        client_pid = session_data['client_pid']
        watch_id = session_data['watch_id']

        valid_signals = session_data['signals']
        signal_config = [(0, 0, sig) for sig in valid_signals]

        valid_controls = session_data['controls']
        bogus_controls = [(0, 0, 'invalid_frequency'), (0, 0, 'invalid_energy')]
        control_config = [(0, 0, con) for con in valid_controls]
        control_config.extend(bogus_controls)

        err_msg = re.escape('Requested controls that are not in allowed list: {}' \
                            .format(sorted({bc[2] for bc in bogus_controls})))

        with self.assertRaisesRegex(RuntimeError, err_msg):
            self._platform_service.start_batch(client_pid, signal_config,
                                               control_config)

        bogus_signals = [(0, 0, 'invalid_uncore'), (0, 0, 'invalid_power')]
        signal_config.extend(bogus_signals)

        err_msg = re.escape('Requested signals that are not in allowed list: {}' \
                            .format(sorted({bs[2] for bs in bogus_signals})))
        with self.assertRaisesRegex(RuntimeError, err_msg):
            self._platform_service.start_batch(client_pid, signal_config,
                                               control_config)

    def test_start_batch_write_blocked(self):
        """Write mode batch server will not start when write lock is held

        This test calls write_control without a session leader, and then a
        different PID tries to create a write mode batch server with a session
        leader.  This request should fail.

        """
        client_pid = 999
        other_pid = 666
        control_name = 'geopm'
        domain = 7
        domain_idx = 42
        setting = 777
        session_data = self.open_mock_session('other', other_pid)

        self._mock_write_lock.try_lock.return_value = other_pid
        with mock.patch('geopmdpy.pio.write_control', return_value=[]) as mock_write_control, \
             mock.patch('geopmdpy.pio.save_control_dir'):
            self._platform_service.write_control(other_pid, control_name, domain, domain_idx, setting)
            mock_write_control.assert_called_once_with(control_name, domain, domain_idx, setting)

        session_data = self.open_mock_session('', client_pid)
        valid_signals = session_data['signals']
        valid_controls = session_data['controls']
        signal_config = [(0, 0, sig) for sig in valid_signals]
        control_config = [(0, 0, con) for con in valid_controls]
        err_msg = f'The PID {client_pid} requested write access, but the geopm service already has write mode client with PID or SID of {self._client_sid[0]}'

        with self.assertRaisesRegex(RuntimeError, err_msg), \
             mock.patch('geopmdpy.pio.start_batch_server', return_value = (2345, "2345")):
            self._platform_service.start_batch(client_pid, signal_config,
                                               control_config)

    def test_start_batch(self):
        session_data = self.open_mock_session('')
        client_pid = session_data['client_pid']
        watch_id = session_data['watch_id']

        valid_signals = session_data['signals']
        valid_controls = session_data['controls']
        signal_config = [(0, 0, sig) for sig in valid_signals]
        control_config = [(0, 0, con) for con in valid_controls]

        expected_result = (1234, "1234")

        self._mock_write_lock.try_lock.return_value = client_pid
        with mock.patch('geopmdpy.pio.start_batch_server', return_value=expected_result), \
             mock.patch('geopmdpy.pio.save_control_dir'):
            actual_result = self._platform_service.start_batch(client_pid, signal_config,
                                                               control_config)
        self.assertEqual(expected_result, actual_result,
                         msg='start_batch() did not pass back correct result')

        save_dir = os.path.join(self._platform_service._RUN_PATH,
                                self._platform_service._SAVE_DIR)
        self.assertTrue(os.path.isdir(save_dir),
                        msg = 'Directory does not exist: {}'.format(save_dir))

        self._mock_active_sessions.get_batch_server.return_value = expected_result[0]
        with mock.patch('geopmdpy.pio.stop_batch_server', return_value=[]) as mock_stop_batch_server, \
             mock.patch('psutil.pid_exists', return_value=True) as mock_pid_exists:
            self._platform_service.stop_batch(client_pid, expected_result[0])
            mock_stop_batch_server.assert_called_once_with(expected_result[0])

    def test_stop_batch_invalid(self):
        with self.assertRaisesRegex(RuntimeError, self._check_client_active_err_msg):
            self._platform_service.stop_batch('', '')

    def test_read_signal_invalid(self):
        with self.assertRaisesRegex(RuntimeError, self._check_client_active_err_msg):
            self._platform_service.read_signal('', '', '', '')

        session_data = self.open_mock_session('')
        client_pid = session_data['client_pid']

        signal_name = 'geopm'
        err_msg = 'Requested signal that is not in allowed list: {}'.format(signal_name)
        with self.assertRaisesRegex(RuntimeError, err_msg):
            self._platform_service.read_signal(client_pid, signal_name, '', '')

    def test_read_signal(self):
        session_data = self.open_mock_session('')
        client_pid = session_data['client_pid']

        signal_name = 'energy'
        domain = 7
        domain_idx = 42
        with mock.patch('geopmdpy.pio.read_signal', return_value=[]) as rs:
            self._platform_service.read_signal(client_pid, signal_name, domain, domain_idx)
            rs.assert_called_once_with(signal_name, domain, domain_idx)

    def test_write_control_invalid(self):
        with self.assertRaisesRegex(RuntimeError, self._check_client_active_err_msg):
            self._platform_service.write_control('', '', '', '', '')

        session_data = self.open_mock_session('')
        client_pid = session_data['client_pid']

        control_name = 'energy'
        err_msg = 'Requested control that is not in allowed list: {}'.format(control_name)
        with self.assertRaisesRegex(RuntimeError, err_msg):
            self._platform_service.write_control(client_pid, control_name, '', '', '')

    def test_write_control(self):
        session_data = self.open_mock_session('')
        client_pid = session_data['client_pid']

        self._mock_write_lock.try_lock.return_value = client_pid
        control_name = 'geopm'
        domain = 7
        domain_idx = 42
        setting = 777
        with mock.patch('geopmdpy.pio.write_control', return_value=[]) as mock_write_control, \
             mock.patch('geopmdpy.pio.save_control_dir'):
            self._platform_service.write_control(client_pid, control_name, domain, domain_idx, setting)
            mock_write_control.assert_called_once_with(control_name, domain, domain_idx, setting)

    def test_get_cache(self):
        topo = mock.MagicMock()
        topo_service = TopoService(topo=topo)

        mock_open = mock.mock_open(read_data='data')
        cache_file = '/run/geopm-service/geopm-topo-cache'
        with mock.patch('builtins.open', mock_open):
            cache_data = topo_service.get_cache()
            self.assertEqual('data', cache_data)
            topo.assert_has_calls([mock.call.create_cache()])
            calls = [mock.call(cache_file),
                     mock.call().__enter__(),
                     mock.call().read(),
                     mock.call().__exit__(None, None, None)]
            mock_open.assert_has_calls(calls)


if __name__ == '__main__':
    unittest.main()
