/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "../../main/cpp/InferenceStatus.h"

enum class ModelStatus {
    Success,
    InvalidInput,
    ExecutionFailed,
};

static_assert(!IsInferenceFailure(ModelStatus::Success, ModelStatus::Success),
    "InitIOTensors success must continue to the app");
static_assert(IsInferenceFailure(ModelStatus::InvalidInput, ModelStatus::Success),
    "InitIOTensors failure must be returned to the app");
static_assert(!IsInferenceFailure(ModelStatus::Success, ModelStatus::Success),
    "RunModel success must continue to the app");
static_assert(IsInferenceFailure(ModelStatus::ExecutionFailed, ModelStatus::Success),
    "RunModel failure must be returned to the app");

int main()
{
    return 0;
}
