import os
import sys
from vunit import VUnit
from pathlib import Path

import resource
resource.setrlimit(resource.RLIMIT_STACK, (resource.RLIM_INFINITY, resource.RLIM_INFINITY))

# Set simulator environment variable (optional if already set)
#simulator = "ghdl"  # Change to "modelsim" to use ModelSim
simulator = "ghdl" 

if simulator == "ghdl":
    os.environ["VUNIT_SIMULATOR"] = "ghdl"
    xilinx_lib_dir = "/xilinx_libs_ghdl"

    
else:
    raise ValueError(f"Unknown simulator: {simulator}")
# Create VUnit instance by parsing command line arguments
vu = VUnit.from_argv()

if simulator == "ghdl":
    # # Base path
    # unisim_path = Path("/opt/Xilinx/Vivado/2021.1/data/vhdl/src/unisims")
    # unisim_pkg = vu.add_library("unisim")
    # # Add top-level support packages
    # for f in ["unisim_VCOMP.vhd", "unisim_VPKG.vhd"]:
    #     f_path = unisim_path / f
    #     src = unisim_pkg.add_source_file(str(f_path), vhdl_standard="2008")
    #     src.add_compile_option("ghdl.a_flags", ["-fsynopsys", "-frelaxed-rules"])

    # # Add primitive files with relaxed rules
    # primitive_files = list((unisim_path / "primitive").glob("*.vhd"))
    # for f in primitive_files:
    #     src = unisim_pkg.add_source_file(str(f), vhdl_standard="2008")
    #     src.add_compile_option("ghdl.a_flags",  ["-frelaxed-rules",  "-fsynopsys", "--warn-no-vital-generic"])
    vu.add_external_library("unisim", os.path.join(xilinx_lib_dir, "unisim/v08"))


# Specify the path to your HDL files
hdl_path = os.path.join(os.path.dirname(__file__), "../")

# Print hdl_path
print("HDL Path:", hdl_path)
# Create a library named 'utils'
utils_pkg = vu.add_library("utils")
utils_pkg.add_source_files(os.path.join(hdl_path, "rtl/utils", "utils_pkg.vhd"))


utils_pkg.add_source_files(os.path.join(hdl_path, "rtl/utils", "fifo_fwft.vhd"))
utils_pkg.add_source_files(os.path.join(hdl_path, "rtl/utils", "dp_lutram.vhd"))
utils_pkg.add_source_files(os.path.join(hdl_path, "rtl/utils", "sdp_bram.vhd"))
#utils_pkg.set_compile_option("ghdl.a_flags", ["--std=93"])

# Create a library named 'lib'
scale_ip_lib = vu.add_library("scale_ip")
scale_ip_lib.add_source_files(os.path.join(hdl_path, "rtl/", "scale_eng.vhd"), vhdl_standard="2008")
scale_ip_lib.add_source_files(os.path.join(hdl_path, "rtl/", "scale_fsm_hor.vhd"), vhdl_standard="2008")
scale_ip_lib.add_source_files(os.path.join(hdl_path, "rtl/", "scale_fsm_vert.vhd"), vhdl_standard="2008")
scale_ip_lib.add_source_files(os.path.join(hdl_path, "rtl/", "scale_pkg.vhd"), vhdl_standard="2008")
scale_ip_lib.add_source_files(os.path.join(hdl_path, "rtl/", "scale_reg.vhd"), vhdl_standard="2008")
scale_ip_lib.add_source_files(os.path.join(hdl_path, "rtl/", "scale_top.vhd"), vhdl_standard="2008")
scale_ip_lib.add_source_files(os.path.join(hdl_path, "rtl/coef/", "*.vhd"), vhdl_standard="2008")
#scale_ip_lib.set_compile_option("ghdl.a_flags", ["--std=93"])


#vu.add_osvvm()


# Create OSVVM Libraries
osvvm_common = vu.add_library("osvvm_common")
osvvm_common.add_source_files("/opt/OsvvmLibraries/Common/src/*.vhd")
# Add OSVVM AXI4 Common (needed for AXI4-Lite)
osvvm_axi4 = vu.add_library("osvvm_axi4")
osvvm_axi4.add_source_files("/opt/OsvvmLibraries/AXI4/common/src/*.vhd")
# Add OSVVM AXI4 Model (needed for transactions)
osvvm_axi4.add_source_files("/opt/OsvvmLibraries/AXI4/Axi4/src/*.vhd")
# Add OSVVM AXI4-Lite (now it should compile correctly)
osvvm_axi4.add_source_files("/opt/OsvvmLibraries/AXI4/Axi4Lite/src/*.vhd")


#osvvm_lib.add_source_files("/opt/OsvvmLibraries/osvvm/*.vhd")
osvvm_lib = vu.add_library("osvvm")
osvvm_path = Path("/opt/OsvvmLibraries/osvvm")

# Compile in dependency order
osvvm_lib.add_source_file(osvvm_path / "OsvvmContext.vhd")
osvvm_lib.add_source_file(osvvm_path / "TranscriptPkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "OsvvmGlobalPkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "TextUtilPkg.vhd") 
osvvm_lib.add_source_file(osvvm_path / "AlertLogPkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "NamePkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "SortListPkg_int.vhd")
osvvm_lib.add_source_file(osvvm_path / "RandomBasePkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "RandomPkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "RandomProcedurePkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "NameStorePkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "ResolutionPkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "MessageListPkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "VendorCovApiPkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "CoveragePkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "MemoryPkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "ResizePkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "TbUtilPkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "ScoreboardGenericPkg.vhd")
osvvm_lib.add_source_file(osvvm_path / "ScoreboardPkg_slv.vhd")
osvvm_lib.add_source_file(osvvm_path / "ScoreboardPkg_int.vhd")
osvvm_lib.add_source_file(osvvm_path / "ReportPkg.vhd")
# osvvm_lib.add_source_file(osvvm_path / "VendorCovApiPkg.vhd")

# Create a library named 'tb_lib'
tb_lib = vu.add_library("tb_lib")
tb_lib.add_source_files(os.path.join(hdl_path, "tb/tb_scale.vhd"))

# Include VUnit's AXI4-Lite Master
vu.add_verification_components()

tb = tb_lib.entity("tb_scale")
#test = tb.test("default")
tb.add_config(name="default", generics=dict(HOR_RES_OUT=1280,VER_RES_OUT=720,csv_i="in_image.csv",csv_o="img_out"))

# Add testbench configuration
#tb.add_config(name="default", generics=dict(runner_cfg=""))
# Set simulation options
if simulator == "ghdl":
    vu.set_sim_option("ghdl.elab_flags", ["-frelaxed"])
    #vu.set_sim_option("ghdl.sim_flags", ["--ieee-asserts=disable-at-0", "--backtrace"])
    #vu.set_sim_option("ghdl.sim_flags", ["--wave=none"])

 
vu.main()

