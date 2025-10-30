#!/bin/bash
set -e

# Adjust this to point to your Vivado installation
VIVADO_PATH="/opt/Xilinx/Vivado/2021.1"
LIB_DEST="/xilinx_libs_ghdl"

# GHDL options
GHDL_OPTS="--std=08 --warn-no-hide"

# Create output directories
mkdir -p $LIB_DEST

mkdir -p $LIB_DEST/unisim
mkdir -p $LIB_DEST/unimacro

# Compile UNISIM

UNISIM_FILES=$(find "$VIVADO_PATH/data/vhdl/src/unisims" -name "*.vhd" \
  | grep -v unisim_retarget_VCOMP \
  | grep -v retarget_VCOMP)

#echo "UNISIM FILES:"
#echo $UNISIM_FILES

echo "Building list of unisim files..."
UNISIM_FILES=$(find "$VIVADO_PATH/data/vhdl/src/unisims" -name "*.vhd" | grep -v retarget_VCOMP)
# \
#  | grep -v unisim_retarget_VCOMP \
#  | grep -v retarget_VCOMP)

echo "$UNISIM_FILES" | while read -r file; do
  echo "Testing file: $file"
  ghdl -i --std=08 --work=unisim --workdir=/xilinx_libs_ghdl/unisim "$file" || {
    echo "❌ Failed on: $file"
    exit 1
  }
done

ghdl -m --work=unisim vcomponents

#ghdl -m $GHDL_OPTS --work=unisim --workdir=$LIB_DEST/unisim

echo "Building list of unimacro files..."
UNIMACRO_FILES=$(find "$VIVADO_PATH/data/vhdl/src/unimacro" -name "*.vhd")

echo "$UNIMACRO_FILES" | while read -r file; do
  echo "Testing file: $file"
  ghdl -i --std=08 --work=unimacro --workdir=/xilinx_libs_ghdl/unimacro "$file" || {
    echo "❌ Failed on: $file"
    exit 1
  }
done

echo "🔧 Compiling dist_mem_gen_v8_0_13..."

DIST_MEM_PATH="$VIVADO_PATH/data/ip/dist_mem_gen_v8_0_13"
DIST_MEM_WORKDIR="$LIB_DEST/dist_mem_gen_v8_0_13"

mkdir -p "$DIST_MEM_WORKDIR"

DIST_MEM_FILES=$(find "$DIST_MEM_PATH" -name "*.vhd")

echo "$DIST_MEM_FILES" | while read -r file; do
  echo "📄 [dist_mem_gen_v8_0_13] $file"
  ghdl -i $GHDL_OPTS --work=dist_mem_gen_v8_0_13 --workdir="$DIST_MEM_WORKDIR" "$file"
done



#ghdl -m $GHDL_OPTS --work=unimacro --workdir=$LIB_DEST/unimacro

# (Optional) Compile SECUREIP if you want it (often has encrypted files)
# Usually, GHDL can't simulate encrypted SecureIP VHDL, so skip unless needed.

# Compile SIMPRIMS if available
if [ -d "$VIVADO_PATH/data/vhdl/src/simprims" ]; then
  echo "Compiling simprim..."
  ghdl -i $GHDL_OPTS \
    -P$LIB_DEST/simprim \
    --work=simprim \
    $(find $VIVADO_PATH/data/vhdl/src/simprims -name "*.vhd") \
    --workdir=$LIB_DEST/simprim

 # ghdl -m $GHDL_OPTS --work=simprim --workdir=$LIB_DEST/simprim
fi

echo "Xilinx libraries compiled into: $LIB_DEST"

