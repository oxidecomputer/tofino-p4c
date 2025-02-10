# dependencies to install: libboost, bdw-gc, pyinstaller
# pip3 install jsl

if [ ! -d ./rapidjson ]; then
    git clone https://github.com/Tencent/rapidjson.git
fi

PATH=$PATH:/usr/gnu/bin/:~/.local/bin
CMAKE_PREFIX_PATH=/opt/ooce/:`pwd`/rapidjson cmake \
	-DENABLE_BMV2=OFF \
	-DENABLE_EBPF=OFF \
	-DENABLE_P4TC=OFF \
	-DENABLE_UBPF=OFF \
	-DENABLE_TOFINO=ON \
	-DENABLE_P4TEST=OFF \
	-DENABLE_TEST_TOOLS=OFF \
	-DENABLE_GC=OFF \
	-DP4C_USE_PREINSTALLED_ABSEIL=ON \
	-Dabsl_DIR=/opt/ooce/absl/lib/cmake/absl \
	-DBoost_INCLUDE_DIR=/opt/ooce/boost/libs \
	-DBoost_USE_STATIC_RUNTIME=ON \
	.. 

# in oxide/_deps/z3-src/src/ast/rewriter/seq_eq_solver.cpp, need to patch
# 287         if (es.size() > (sz + log2((double)10)-1)/log2((double)10)) {
gmake -j 8
