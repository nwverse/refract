import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("probe_target", Path(__file__).with_name("probe_target.py"))
probe_target = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe_target)
find_simulator_targets = probe_target.find_simulator_targets


UDID = "00000000-0000-0000-0000-000000000001"


def simulator_device(udid=UDID):
    """Synthetic metadata matching the pinned Xcode 27.2 output shape."""
    return {
        "identifier": udid,
        "deviceProperties": {
            "name": "Synthetic allocated simulator",
            "bootState": "booted",
            "osVersionNumber": "27.0",
            "provider": "com.apple.CoreSimulator.SimulatorCoreDevicePlugin",
        },
        "hardwareProperties": {
            "udid": udid,
            "reality": "simulated",
            "marketingName": "Synthetic iPhone",
        },
        "properties": {
            "hardware": {"udid": udid},
            "software": {"osVersionNumber": {"stringValue": "27.0"}},
            "state": {"bootState": "booted"},
        },
    }


class SimulatorTargetTest(unittest.TestCase):
    def test_nested_hardware_udid_is_not_a_second_target(self):
        payload = {"result": {"devices": [simulator_device()]}}
        self.assertEqual(find_simulator_targets(payload, UDID), payload["result"]["devices"])

    def test_two_full_device_objects_are_ambiguous(self):
        payload = {"result": {"devices": [simulator_device(), simulator_device()]}}
        self.assertEqual(len(find_simulator_targets(payload, UDID)), 2)

    def test_nested_hardware_udid_without_a_device_is_rejected(self):
        payload = {"result": {"devices": [{"hardwareProperties": {"udid": UDID}}]}}
        self.assertEqual(find_simulator_targets(payload, UDID), [])

    def test_physical_device_cannot_be_selected_as_a_simulator(self):
        device = simulator_device()
        device["hardwareProperties"]["reality"] = "physical"
        self.assertEqual(find_simulator_targets({"result": {"devices": [device]}}, UDID), [])

    def test_unavailable_or_non_booted_device_is_rejected(self):
        for state in ("unavailable", "shutdown"):
            device = simulator_device()
            device["deviceProperties"]["bootState"] = state
            with self.subTest(state=state):
                self.assertEqual(find_simulator_targets({"result": {"devices": [device]}}, UDID), [])


if __name__ == "__main__":
    unittest.main()
