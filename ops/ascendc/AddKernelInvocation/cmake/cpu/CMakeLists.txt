# cpu
# Kirin9030/KirinX90 的 CPU 调试模式
# 说明: tikicpulib-config.cmake 中 tikicpulib::Kirin9030 是悬空 ALIAS target
#       (targets-tikicpulib.cmake 只 IMPORT 了 ascend910/310p/910B1/310B1/950pr_9599 五个实体),
#       因此这里不 find_package, 直接链接实体 so:
#       - tools/tikicpulib/lib64/Kirin9030/libcpudebug.so   (AscendC::GmAlloc / SetKernelMode / ICPU_RUN_KF 运行时)
#       - tools/tikicpulib/lib64/libcpudebug_stubreg.so     (寄存器 stub)
#       - x86_64-linux/simulator/Kirin9030/lib/libpem_davinci.so (完整版 libcpudebug.so 的 pvmodel 依赖:
#         pv_init/pv_step/pv_mem_read/pv_mem_write/pv_reg_read/pv_reg_write/pv_launch_sub_core/set_read_record)
# 编译宏 ASCENDC_CPU_DEBUG=1 使 sys_macros.h 引入 tikicpulib 的 stub_def.h,
# 将 __global__/__aicore__ 重定义为空, 使 g++ 可编译设备侧源码.

file(GLOB SRC_FILES
    ${CMAKE_SOURCE_DIR}/*.cpp
)
list(REMOVE_ITEM SRC_FILES ${CMAKE_SOURCE_DIR}/add_custom.cpp ${CMAKE_SOURCE_DIR}/add_custom_micro.cpp)
list(APPEND SRC_FILES ${KERNEL_SRC})

add_executable(${smoke_testcase}_cpu
    ${SRC_FILES}
)

target_include_directories(${smoke_testcase}_cpu PRIVATE
    # tikicpulib CPU stub 头 (stub_def.h / stub_fun.h / kern_fwk.h / tikicpulib.h)
    ${ASCEND_INSTALL_PATH}/tools/tikicpulib/include
    # AscendC 设备侧头 (kernel_operator.h 及 basic_api/interface/impl 树)
    ${ASCEND_INSTALL_PATH}/x86_64-linux/asc/include
    ${ASCEND_INSTALL_PATH}/x86_64-linux/asc/include/basic_api
    ${ASCEND_INSTALL_PATH}/x86_64-linux/asc/include/interface
    ${ASCEND_INSTALL_PATH}/x86_64-linux/asc
    # 高阶 API 的 kernel_tiling
    ${ASCEND_INSTALL_PATH}/x86_64-linux/ascendc/include/highlevel_api
    # securec.h (kern_fwk.h 依赖, libc_sec 对应头)
    ${ASCEND_INSTALL_PATH}/x86_64-linux/include
    ${CMAKE_SOURCE_DIR}
)

target_compile_definitions(${smoke_testcase}_cpu PRIVATE
    ASCENDC_CPU_DEBUG=1
    ASCENDC_DEBUG=1
    # Kirin9030 = dav-l311 (NpuArch 3113); KirinX90 = dav-l300 (3003)
    # sys_macros.h / kernel_utils_mode_cpu.h / kernel_utils_constants.h 按 __NPU_ARCH__ 分派
    $<IF:$<STREQUAL:${ASCEND_PRODUCT_TYPE},Kirin9030>,__CCE_AICORE__=311;__DAV_L311__;__NPU_ARCH__=3113,__CCE_AICORE__=300;__DAV_L300__;__NPU_ARCH__=3003>
    _GLIBCXX_USE_CXX11_ABI=0
)

target_compile_options(${smoke_testcase}_cpu PRIVATE
    -g
    -std=c++17
)

target_link_directories(${smoke_testcase}_cpu PRIVATE
    # libcpudebug.so 的运行时依赖 (libc_sec/libmmpa/libunified_dlog) 在 lib64
    ${ASCEND_INSTALL_PATH}/lib64
    ${ASCEND_INSTALL_PATH}/tools/tikicpulib/lib64
    # Kirin9030 专属 libcpudebug.so / libtikcpp_debug.so
    ${ASCEND_INSTALL_PATH}/tools/tikicpulib/lib64/${ASCEND_PRODUCT_TYPE}
    # 完整版 libcpudebug.so 的 pvmodel 依赖 (libpem_davinci.so)
    ${ASCEND_INSTALL_PATH}/x86_64-linux/simulator/${ASCEND_PRODUCT_TYPE}/lib
)

target_link_libraries(${smoke_testcase}_cpu PRIVATE
    cpudebug
    cpudebug_stubreg
    pem_davinci
    c_sec
    mmpa
    unified_dlog
    pthread
)

set_target_properties(${smoke_testcase}_cpu PROPERTIES
    OUTPUT_NAME ${smoke_testcase}_${ASCEND_RUN_MODE}
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}
)

# 运行时需将下列目录加入 LD_LIBRARY_PATH (run_cpu.sh 已自动设置):
#   export LD_LIBRARY_PATH=${ASCEND_INSTALL_PATH}/tools/tikicpulib/lib64:${ASCEND_INSTALL_PATH}/tools/tikicpulib/lib64/Kirin9030:${ASCEND_INSTALL_PATH}/x86_64-linux/simulator/Kirin9030/lib:${ASCEND_INSTALL_PATH}/lib64:$LD_LIBRARY_PATH
