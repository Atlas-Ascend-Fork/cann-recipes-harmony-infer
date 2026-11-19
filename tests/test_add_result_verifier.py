# Copyright (c) 2026, HUAWEI CORPORATION.  All rights reserved.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
import importlib.util
import tempfile
import unittest
from pathlib import Path

import numpy as np


def load_verifier():
    path = Path(__file__).resolve().parents[1] / "ops/ascendc/AddKernelInvocation/scripts/verify_result.py"
    spec = importlib.util.spec_from_file_location("add_verifier", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.verify_result


class VerifierTest(unittest.TestCase):
    def check_files(self, output, golden):
        with tempfile.TemporaryDirectory() as directory:
            output_path = Path(directory) / "output.bin"
            golden_path = Path(directory) / "golden.bin"
            output_path.write_bytes(output)
            golden_path.write_bytes(golden)
            return load_verifier()(output_path, golden_path)

    def test_equal_arrays_pass(self):
        data = np.array([1.0, 2.0, 3.0], dtype=np.float16).tobytes()
        self.assertTrue(self.check_files(data, data))

    def test_truncated_single_element_cannot_broadcast(self):
        output = np.ones(1, dtype=np.float16).tobytes()
        golden = np.ones(4, dtype=np.float16).tobytes()
        self.assertFalse(self.check_files(output, golden))

    def test_partial_element_is_rejected(self):
        data = np.ones(1, dtype=np.float16).tobytes() + b"x"
        self.assertFalse(self.check_files(data, data))

    def test_empty_files_are_rejected(self):
        self.assertFalse(self.check_files(b"", b""))


if __name__ == "__main__":
    unittest.main()
