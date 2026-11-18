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
import unittest
from pathlib import Path

import numpy as np


def load_generator():
    path = Path(__file__).resolve().parents[1] / "ops/ascendc/src/gather_dequant_int8_custom/test/gen_data.py"
    spec = importlib.util.spec_from_file_location("gather_generator", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ConstantEmbeddingRowTest(unittest.TestCase):
    def test_constant_rows_have_finite_quantization_and_golden(self):
        module = load_generator()
        for value in [0.0, 0.5, -0.5, 1e-6, -1e-6]:
            with self.subTest(value=value):
                weight = np.full((1, 8), value, dtype=np.float32)
                table, scale, zero_point = module.quantize_embedding(weight)
                self.assertTrue(np.all(np.isfinite(scale)))
                self.assertTrue(np.all(scale > 0))
                self.assertTrue(np.all(np.isfinite(zero_point)))
                output = module.gather_dequant_int8_ref(table, np.array([[0]], dtype=np.int32), scale, zero_point)
                self.assertTrue(np.all(np.isfinite(output)))
                np.testing.assert_allclose(output, weight.astype(np.float16).reshape(1, 1, 8), rtol=0.005, atol=1e-7)

    def test_nonconstant_row_quantization_is_unchanged(self):
        module = load_generator()
        weight = np.array([[-0.5, 0.0, 0.5]], dtype=np.float64)
        table, scale, zero_point = module.quantize_embedding(weight)
        expected_scale = (weight.max(axis=1) - weight.min(axis=1)) / 255.0
        expected_zp = -weight.min(axis=1) / expected_scale
        shifted = weight / expected_scale[:, None] + expected_zp[:, None]
        expected_table = np.clip(np.round(shifted), 0, 255).astype(np.uint8)
        np.testing.assert_array_equal(table, expected_table)
        np.testing.assert_array_equal(scale, expected_scale.astype(np.float16))
        np.testing.assert_array_equal(zero_point, expected_zp.astype(np.float16))


if __name__ == "__main__":
    unittest.main()
