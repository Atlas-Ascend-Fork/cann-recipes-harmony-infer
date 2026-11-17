#!/bin/bash
# Copyright (c) 2025, HUAWEI CORPORATION.  All rights reserved.
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
#
# CPU 调试模式专用脚本（由 run.sh 拆分而来）
# 用法:
#   bash run_cpu.sh -v Kirin9030 [选项]
# 选项:
#   -v, --soc-version   SoC 型号: Kirin9030 / KirinX90（默认 Kirin9030）
#   -i, --install-path  CANN 安装路径（默认取 $ASCEND_HOME_PATH）
#   --skip-build        跳过编译+数据生成（复用已有 add_cpu 与 input/*.bin）
#   --skip-verify       跳过精度校验
#
# 环境要求: 完整版 libcpudebug.so (官方 toolkit 安装, 约 3MB/5522 符号;
#           源码仓 asc-tools 自构建的精简版 809KB/2237 符号缺 pv_*/ProcessLock 等符号, 不可用)
# 运行时依赖 (LD_LIBRARY_PATH 自动设置):
#   tools/tikicpulib/lib64                        公共 stub 库
#   tools/tikicpulib/lib64/Kirin9030              Kirin9030 专属 libcpudebug.so
#   x86_64-linux/simulator/Kirin9030/lib          libpem_davinci.so (pvmodel)
#   lib64                                         libc_sec/libmmpa/libunified_dlog
# 运行后会在 cwd 生成 simlog/ (pvmodel 日志) 与 stub_reg.log (dlsym 注册记录)

export PRINT_TIK_MEM_ACCESS=FALSE

CURRENT_DIR=$(
    cd $(dirname ${BASH_SOURCE:-$0})
    pwd
); cd $CURRENT_DIR

declare -A VersionMap
#kirin
VersionMap["KirinX90"]="KirinX90"
VersionMap["Kirin9030"]="Kirin9030"
#迁移算子修改点：FILE_NAME控制编译获得的二进制名
FILE_NAME="add"
RUN_MODE="cpu"

SHORT=v:,i:
LONG=soc-version:,install-path:,skip-build,skip-verify
OPTS=$(getopt -a --options $SHORT --longoptions $LONG -- "$@")
eval set -- "$OPTS"

SOC_VERSION="Kirin9030"
SKIP_BUILD=0
SKIP_VERIFY=0

while :; do
    case "$1" in
    -v | --soc-version)
        SOC_VERSION="$2"
        shift 2
        ;;
    -i | --install-path)
        ASCEND_INSTALL_PATH="$2"
        shift 2
        ;;
    --skip-build)
        SKIP_BUILD=1
        shift
        ;;
    --skip-verify)
        SKIP_VERIFY=1
        shift
        ;;
    --)
        shift
        break
        ;;
    *)
        echo "[ERROR] Unexpected option: $1"
        exit 1
        ;;
    esac
done

if [ -n "$ASCEND_INSTALL_PATH" ]; then
    _ASCEND_INSTALL_PATH=$ASCEND_INSTALL_PATH
elif [ -n "$ASCEND_HOME_PATH" ]; then
    _ASCEND_INSTALL_PATH=$ASCEND_HOME_PATH
else
    if [ -d "$HOME/Ascend/ascend-toolkit/latest" ]; then
        _ASCEND_INSTALL_PATH=$HOME/Ascend/ascend-toolkit/latest
    else
        _ASCEND_INSTALL_PATH=/usr/local/Ascend/ascend-toolkit/latest
    fi
fi

if [[ " ${!VersionMap[*]} " != *" $SOC_VERSION "* ]]; then
    echo "ERROR: SOC_VERSION should be in [${!VersionMap[*]}]"
    exit 1
fi
_SOC_VERSION=${VersionMap[$SOC_VERSION]}

if  [ $_SOC_VERSION"x" = "KirinX90x" ] || [ $_SOC_VERSION"x" = "Kirin9030x" ]; then
    CORE_TYPE="AiCore"
fi

# CPU 模式运行库搜索路径:
#   tikicpulib 公共库 + Kirin 专属 cpudebug + simulator 的 pvmodel + 运行时公共库
export LD_LIBRARY_PATH=$_ASCEND_INSTALL_PATH/tools/tikicpulib/lib64:$_ASCEND_INSTALL_PATH/tools/tikicpulib/lib64/${_SOC_VERSION}:$_ASCEND_INSTALL_PATH/x86_64-linux/simulator/${_SOC_VERSION}/lib:$_ASCEND_INSTALL_PATH/lib64:$LD_LIBRARY_PATH

# 前置检查: libcpudebug.so 必须是完整版 (>= 2MB); 精简版 (809KB, 源码仓自构建) 会因缺符号失败
_CPUDEBUG_SO=$_ASCEND_INSTALL_PATH/tools/tikicpulib/lib64/${_SOC_VERSION}/libcpudebug.so
if [ -f "$_CPUDEBUG_SO" ]; then
    _SO_SIZE=$(stat -c %s "$_CPUDEBUG_SO")
    if [ "$_SO_SIZE" -lt 2000000 ]; then
        echo "[ERROR] $_CPUDEBUG_SO 只有 ${_SO_SIZE} 字节, 是精简版 (缺 pv_*/ProcessLock 等符号)!"
        echo "        请用官方 toolkit 重装 (如: Ascend-cann-toolkit_9.3.0~weekly.20261014.01),"
        echo "        勿用源码仓 asc-tools 自构建的 cann-asc-tools 包覆盖。"
        exit 1
    fi
else
    echo "[ERROR] not found: $_CPUDEBUG_SO"
    exit 1
fi

if [ "$SKIP_BUILD" -eq 0 ]; then
    set -e
    rm -rf build *_cpu *_sim *_npu cceprint npuchk *.vcd
    mkdir -p build
    cmake -B build \
        -Dsmoke_testcase=${FILE_NAME} \
        -DASCEND_PRODUCT_TYPE=${_SOC_VERSION} \
        -DASCEND_CORE_TYPE=${CORE_TYPE} \
        -DASCEND_RUN_MODE=${RUN_MODE} \
        -DASCEND_INSTALL_PATH=${_ASCEND_INSTALL_PATH}
    cmake --build build --target ${FILE_NAME}_${RUN_MODE}
    if [ $? -ne 0 ]; then
        echo "ERROR: compile op on ${RUN_MODE} failed!"
        exit -1
    fi
    echo "INFO: compile op on ${RUN_MODE} succeed!"

    rm -rf input/*.bin output/*.bin
    python3 scripts/gen_data.py
else
    if [ ! -x "./${FILE_NAME}_${RUN_MODE}" ]; then
        echo "ERROR: --skip-build 指定但 ./${FILE_NAME}_${RUN_MODE} 不存在, 请先正常执行一次!"
        exit 1
    fi
    echo "INFO: skip build, reuse ./${FILE_NAME}_${RUN_MODE}"
fi

# 清理上次运行产物
# 注: pvmodel 的日志目录 "./simlog/" 硬编码在 libcpudebug.so 的 KirinPvFactory 中, 无环境变量可改
rm -rf simlog stub_reg.log

./${FILE_NAME}_${RUN_MODE}
if [ $? -ne 0 ]; then
    echo "ERROR: execute op on ${RUN_MODE} failed!"
    exit -1
fi
echo "INFO: execute op on ${RUN_MODE} succeed!"

if [ "$SKIP_VERIFY" -eq 0 ]; then
    python3 scripts/verify_result.py output/output_z.bin output/golden.bin
fi

# CPU 模式无 profiling; simlog/ 与 stub_reg.log 保留供问题排查, 如需清理:
#   rm -rf simlog stub_reg.log
