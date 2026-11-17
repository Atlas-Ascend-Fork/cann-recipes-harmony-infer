/**
 * Copyright (c) Huawei Technologies Co., Ltd. 2026. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "kernel_operator.h"
using namespace AscendC;
using AscendC::Reg::RegTensor;
using AscendC::Reg::MaskReg;
using AscendC::Reg::UpdateMask;
using AscendC::Reg::Add;

// 固定参数版本
//    patmode = 0 -> 用MASK标量
//    memory = 0 -> 结果写新输出buffer
//    mode = 0 -> 单寄存器（RegTraitNumOne）, one_rep_size = GetVecLen() / sizeof(T)
//    MASK < TOTAL_LENGTH, 尾部[MASK, TOTAL_LENGTH]不会被写入，以来输出buffer预清零

constexpr uint32_t TOTAL_LENGTH = 8 * 2048;
constexpr uint32_t MASK = 8 * 2048;
constexpr int32_t BUFFER_NUM = 1;

class KernelMicroAddCustom {
public:
    __aicore__ inline KernelMicroAddCustom() {}
    __aicore__ inline void Init(GM_ADDR x, GM_ADDR y, GM_ADDR z)
    {
        AscendCUtils::SetOverflow(1);
        xGm.SetGlobalBuffer((__gm__ half *)x, TOTAL_LENGTH);
        yGm.SetGlobalBuffer((__gm__ half *)y, TOTAL_LENGTH);
        zGm.SetGlobalBuffer((__gm__ half *)z, TOTAL_LENGTH);
        pipe.InitBuffer(inQueueX, 1, TOTAL_LENGTH * sizeof(half));
        pipe.InitBuffer(inQueueY, 1, TOTAL_LENGTH * sizeof(half));
        pipe.InitBuffer(outQueueZ, 1, TOTAL_LENGTH * sizeof(half));
    }
    __aicore__ inline void Process()
    {
        CopyIn();
        Compute();
        CopyOut();
    }

private:
    __aicore__ inline void CopyIn()
    {
        AscendC::LocalTensor<half> xLocal = inQueueX.AllocTensor<half>();
        AscendC::LocalTensor<half> yLocal = inQueueY.AllocTensor<half>();
        AscendC::DataCopy(xLocal, xGm, TOTAL_LENGTH);
        AscendC::DataCopy(yLocal, yGm, TOTAL_LENGTH);
        inQueueX.EnQue(xLocal);
        inQueueY.EnQue(yLocal);
    }
    __aicore__ inline void static AddFunction(__ubuf__ half* dstPtr, __ubuf__ half* src0Ptr,
        __ubuf__ half* src1Ptr, uint16_t repeattimes, uint16_t one_rep_size)
    {
        AscendC::Reg::RegTensor<half> Src0Reg;
        AscendC::Reg::RegTensor<half> Src1Reg;
        AscendC::Reg::RegTensor<half> DstReg;
        uint32_t sreg = MASK;
        MaskReg maskReg;
        for (uint16_t i = 0; i < repeattimes; i++) {
            maskReg = UpdateMask<half>(sreg);
            LoadAlign(Src0Reg, src0Ptr + i * one_rep_size);
            LoadAlign(Src1Reg, src1Ptr + i * one_rep_size);
            Add(DstReg, Src0Reg, Src1Reg, maskReg);
            StoreAlign(dstPtr + i * one_rep_size, DstReg, maskReg);
        }
    }
    __aicore__ inline void Compute()
    {
        AscendC::LocalTensor<half> xLocal = inQueueX.DeQue<half>();
        AscendC::LocalTensor<half> yLocal = inQueueY.DeQue<half>();
        AscendC::LocalTensor<half> zLocal = outQueueZ.AllocTensor<half>();
        uint16_t one_rep_size = GetVecLen() / sizeof(half);
        uint16_t repeattimes = (MASK + one_rep_size - 1) / one_rep_size;

        __ubuf__ half* src0Ptr = (__ubuf__ half*)xLocal.GetPhyAddr();
        __ubuf__ half* src1Ptr = (__ubuf__ half*)yLocal.GetPhyAddr();
        __ubuf__ half* dstPtr = (__ubuf__ half*)zLocal.GetPhyAddr();
        VF_CALL<AddFunction>(dstPtr, src0Ptr, src1Ptr, repeattimes, one_rep_size);

        outQueueZ.EnQue<half>(zLocal);
        inQueueX.FreeTensor(xLocal);
        inQueueY.FreeTensor(yLocal);
    }
    __aicore__ inline void CopyOut()
    {
        AscendC::LocalTensor<half> zLocal = outQueueZ.DeQue<half>();
        AscendC::DataCopy(zGm, zLocal, TOTAL_LENGTH);
        outQueueZ.FreeTensor(zLocal);
    }

private:
    AscendC::TPipe pipe;
    AscendC::TQue<AscendC::TPosition::VECIN, BUFFER_NUM> inQueueX, inQueueY;
    AscendC::TQue<AscendC::TPosition::VECOUT, BUFFER_NUM> outQueueZ;
    AscendC::GlobalTensor<half> xGm;
    AscendC::GlobalTensor<half> yGm;
    AscendC::GlobalTensor<half> zGm;
};

extern "C" __global__ __aicore__ void add_custom(GM_ADDR x, GM_ADDR y, GM_ADDR z)
{
    KernelMicroAddCustom op;
    op.Init(x, y, z);
    op.Process();
}

// 向main.cpp暴露的调用接口
#ifndef ASCENDC_CPU_DEBUG
void add_custom_do(uint32_t blockDim, void *l2ctrl, void *stream, uint8_t *x, uint8_t *y, uint8_t *z)
{
    add_custom<<<blockDim, l2ctrl, stream>>>(x, y, z);
}
#endif

