-------------------------------------------------------------------------------
-- Video Scaler IP - FPGA-based Video Scaling Solution
-------------------------------------------------------------------------------
-- Copyright (c) 2025 Boris Snajder
-- 
-- This source describes Open Hardware and is licensed under the CERN-OHL-P v2
-- 
-- You may redistribute and modify this source and make products using it under
-- the terms of the CERN-OHL-P v2 (https://ohwr.org/cern_ohl_p_v2.txt).
-- 
-- This source is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY,
-- INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A
-- PARTICULAR PURPOSE. Please see the CERN-OHL-P v2 for applicable conditions.
-- 
-- Source location: https://github.com/bsnajder/video_scaler
-------------------------------------------------------------------------------
-- File: tb_scale.vhd
-- Description: Testbench for video scaler IP. Reads input video data from CSV,
--              feeds it to the scaler, and captures output video data to CSV.
-- Author: Boris Snajder
-- Created: 2025
-- Modified: 2025-09-20
-------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


library vunit_lib;
context vunit_lib.vunit_context;
--use vunit_lib.axi_lite_master_pkg.all;
--context vunit_lib.vc_context;
use vunit_lib.signal_checker_pkg.all;
context vunit_lib.vc_context;


library OSVVM;
context OSVVM.OsvvmContext;
library osvvm_common ;  
use osvvm_common.AddressBusTransactionPkg.all ;
--context osvvm_common.OsvvmCommonContext ;
--use osvvm_common.Axi4InterfaceCommonPkg.all ;
--use osvvm_common.Axi4LiteInterfacePkg.all ; 


library osvvm_axi4;
--use osvvm_axi4.Axi4LiteMasterPkg.all;   -- OSVVM AXI4-Lite Master
use osvvm_Axi4.Axi4LiteMasterComponentPkg.all;
use osvvm_Axi4.Axi4LiteInterfacePkg.all;
--use osvvm_Axi4.Axi4LiteManagerPkg.all ;
use osvvm_Axi4.Axi4OptionsPkg.all;


library scale_ip;
use scale_ip.scale_pkg.all;

entity tb_scale is
    generic (
        runner_cfg      : string;
        tb_path         : string;
        HOR_RES_OUT     : integer := 1920; -- Output horizontal resolution
        VER_RES_OUT     : integer := 1080; -- Output vertical resolution
        csv_i           : string := "nature";
        csv_o           : string := "img_out"
    );
end entity tb_scale;

--architecture declaration
architecture beh of tb_scale is

      -- AXI4Stream Verification Components
      constant data_width : natural := 8*ENG_NUM; 

      constant master_axi_stream : axi_stream_master_t := new_axi_stream_master(
        data_length => data_width*3,
        user_length => 1,
        --stall_config => new_stall_config(0.05, 1, 10)
        stall_config => new_stall_config(0.0, 1, 10)
      );

    
    -- Slave
      constant slave_axi_stream : axi_stream_slave_t := new_axi_stream_slave(
        data_length => data_width*3, -- match tdata width
        user_length => 1,
        stall_config => new_stall_config(0.0, 1, 10)
        --stall_config => new_stall_config(0.1, 1, 20)

  );

    constant m_I : integer_array_t := load_csv(tb_path & csv_i);
    constant m_O : integer_array_t := new_2d(2048*3, 2048, 16, true);

    constant AXI_AWIDTH : positive := 32;
    constant AXI_DWIDTH : positive := 32;
    constant AXI_STRB_WIDTH : integer    := AXI_DWIDTH / 8;

    signal Axi4LiteBus   : Axi4LiteRecType(
        WriteAddress(Addr(AXI_AWIDTH - 1 downto 0)),
        WriteData(Data(AXI_DWIDTH - 1 downto 0), Strb(AXI_STRB_WIDTH - 1 downto 0)),
        ReadAddress(Addr(AXI_AWIDTH - 1 downto 0)),
        ReadData(Data(AXI_DWIDTH - 1 downto 0))
    );
    signal Axi4MemRec    : AddressBusRecType(
        Address(AXI_AWIDTH - 1 downto 0),
        DataToModel(AXI_DWIDTH - 1 downto 0),
        DataFromModel(AXI_DWIDTH - 1 downto 0)
    );   

    signal clk   : std_logic := '0';
    signal reset : std_logic := '1';
    signal resetn : std_logic := '0';

    signal start, done, saved : boolean := false;


    signal m_tvalid, m_tready, m_tlast, s_tvalid, s_tready, s_tlast : std_logic;
    signal m_tdata, s_tdata : std_logic_vector(data_length(master_axi_stream)-1 downto 0); 
    signal m_tkeep, s_tkeep : std_logic_vector(data_length(master_axi_stream)/8-1 downto 0);
    signal m_tstrobe, s_tstrobe : std_logic_vector(data_length(master_axi_stream)/8-1 downto 0);
    signal m_tuser, s_tuser : std_logic_vector(0 downto 0);

    constant AXIL_MASTER_HANDLE : bus_master_t := new_bus(
        data_length    => 32,
        address_length => 32
    );

    signal s_axi_awvalid : std_logic;
    signal s_axi_awready : std_logic;
    signal s_axi_awaddr  : std_logic_vector(AXI_AWIDTH-1 downto 0);
    signal s_axi_awprot  : std_logic_vector(2 downto 0);
    signal s_axi_wvalid  : std_logic;
    signal s_axi_wready  : std_logic;
    signal s_axi_wdata   : std_logic_vector(AXI_DWIDTH-1 downto 0);
    signal s_axi_wstrb   : std_logic_vector(AXI_DWIDTH/8-1 downto 0);
    signal s_axi_bvalid  : std_logic;
    signal s_axi_bready  : std_logic;
    signal s_axi_bresp   : std_logic_vector(1 downto 0);
    signal s_axi_arvalid : std_logic;
    signal s_axi_arready : std_logic;
    signal s_axi_araddr  : std_logic_vector(AXI_AWIDTH-1 downto 0);
    signal s_axi_arprot  : std_logic_vector(2 downto 0);
    signal s_axi_rvalid  : std_logic;
    signal s_axi_rready  : std_logic;
    signal s_axi_rdata   : std_logic_vector(AXI_DWIDTH-1 downto 0);
    signal s_axi_rresp   : std_logic_vector(1 downto 0);    

    constant HOR_RES_IN   : integer := 640; -- Input horizontal resolution
    constant VER_RES_IN   : integer := 480; -- Input vertical resolution
   

    --constant HOR_RES_OUT  : integer := 1920; -- Output horizontal resolution
    --constant VER_RES_OUT  : integer := 1080; -- Output vertical resolution

    constant SIM_FRM_NUM  : integer := 3; -- Number of frames to simulate

    function calculate_scale_factor(
        in_res  : integer;
        out_res : integer
    ) return unsigned is

        variable scale_factor : real;
        variable scale_step : real;
        variable scale_factor_unsigned : unsigned(SCALE_CNT_SIZE-1 downto 0);
    begin
        scale_factor := real(out_res) / real(in_res);
        scale_step := 1.0 / scale_factor;
        scale_factor_unsigned := to_unsigned(integer(scale_step * real(2**SCALE_CNT_FRAC_SIZE)), SCALE_CNT_SIZE); --to have this working, real has to have enough precision
        if scale_factor > 1.0 then
            scale_factor_unsigned := scale_factor_unsigned + to_unsigned(1, SCALE_CNT_SIZE); -- add 1 to the scale factor if it is greater than 1; this is correction due to finite precision of fixed point representation
        end if;
        return scale_factor_unsigned;
    end function;

    signal hor_scale        : std_logic_vector(31 downto 0) := std_logic_vector(resize(calculate_scale_factor(HOR_RES_IN, HOR_RES_OUT), 32)); 
    signal vert_scale       : std_logic_vector(31 downto 0) := std_logic_vector(resize(calculate_scale_factor(VER_RES_IN, VER_RES_OUT), 32)); 

begin
    
    -- Clock generation
    clk_process : process
    begin
        while true loop
            clk <= '0';
            wait for 10 ns;
            clk <= '1';
            wait for 10 ns;
        end loop;
        wait;
    end process clk_process;
    
    -- Test process
    main  : process
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop
            if run("test") then
                -- Initialize
                reset <= '1';
                wait for 100 ns;
                reset <= '0';
                wait for 100 ns;

                vunit_lib.logger_pkg.log("Reset sequence completed");

                wait until rising_edge(clk);
                start <= true;
                wait until rising_edge(clk);
                start <= false;
                wait until (done and saved and rising_edge(clk));
   --             wait until (done and rising_edge(clk));
                info("Test done");
            end if;
        end loop;

        wait for 10 us;
        -- End of test
        vunit_lib.logger_pkg.log("Test process completed");
        test_runner_cleanup(runner);
        wait;
    end process main;

    resetn <= not reset;
    

    stimuli: process
        variable last       : std_logic;
        variable tstrobe    : std_logic_vector(m_tdata'length/8-1 downto 0);
        variable tkeep      : std_logic_vector(m_tdata'length/8-1 downto 0) := (others => '1');
        variable tuser      : std_logic_vector(m_tuser'range) := (others => '0');
        variable pix_data   : unsigned(8*3*2-1 downto 0);
        variable x          : integer;
    begin
        wait until start and rising_edge(clk);
        done <= false;
        wait until rising_edge(clk);


        -- WaitForClock(Axi4MemRec, 10);
        wait_until_idle(net, AXIL_MASTER_HANDLE);
        info("Writing to address 0x08...");
        write_bus(net, AXIL_MASTER_HANDLE, X"00000008", hor_scale);
        wait_until_idle(net, AXIL_MASTER_HANDLE);
        info("Writing to address 0x0C...");
        write_bus(net, AXIL_MASTER_HANDLE, X"0000000C", vert_scale);
        wait_until_idle(net, AXIL_MASTER_HANDLE);
        info("Writing to address 0x10...");
        write_bus(net, AXIL_MASTER_HANDLE, X"00000010", std_logic_vector(to_unsigned(VER_RES_IN, 32)));
        wait_until_idle(net, AXIL_MASTER_HANDLE);

        info("Sending m_I of size " & to_string(height(m_I)) & "x" & to_string(width(m_I)/3) & " to UUT...");

        for frm_cnt in 0 to SIM_FRM_NUM-1 loop
            for y in 0 to height(m_I)-1 loop
                
                x := 0;
                while x < width(m_I)/3 loop
                    wait until rising_edge(clk);
                    
                    if (y = 0 and x = 0) then tuser := (others => '1'); else tuser := (others => '0'); end if;
                
                    if x = width(m_I)/3-1 then last := '1'; else last := '0'; end if;
                    
                    pix_data := (others => '0');    
                    pix_data((0+1)*8-1 downto 0*8) := to_unsigned(get(m_I, x*3, y), 8);
                    pix_data((1+1)*8-1 downto 1*8) := to_unsigned(get(m_I, x*3+1, y), 8);
                    pix_data((2+1)*8-1 downto 2*8) := to_unsigned(get(m_I, x*3+2, y), 8);
                    x := x + 1;
                    tstrobe := (others => '1');
                
                    if (data_width = 16) then
                        if x = width(m_I)/3-1 then last := '1'; else last := last; end if;
                        if (x <= width(m_I)/3) then
                            
                            pix_data((1*3+0+1)*8-1 downto 8*(3+0)) := to_unsigned(get(m_I, x*3, y), 8);
                            pix_data((1*3+1+1)*8-1 downto 8*(3+1)) := to_unsigned(get(m_I, x*3+1, y), 8);
                            pix_data((1*3+2+1)*8-1 downto 8*(3+2)) := to_unsigned(get(m_I, x*3+2, y), 8);
                            x := x + 1;
                            
                        else
                            tstrobe((1+1)*3-1 downto 1*3) := (others => '0');
                        end if;
                    end if;
                    
                    push_axi_stream(net, master_axi_stream, std_logic_vector(pix_data(8*3*ENG_NUM-1 downto 0)) , tlast => last, tkeep => tkeep, tstrb => tstrobe,  tuser => tuser);
                end loop;
            end loop;
            info("frm " & integer'image(frm_cnt) & " sent!");
        end loop;

        info("m_I sent!");

        wait for 10 us;

        wait until rising_edge(clk);
        done <= true;
  end process stimuli;


    save: process
        variable o : std_logic_vector(m_tdata'length-1 downto 0);
        variable o_16 : std_logic_vector(15 downto 0);
        variable last : std_logic:='0';
        variable tstrobe : std_logic_vector(s_tdata'length/8-1 downto 0);
        variable tkeep   : std_logic_vector(s_tdata'length/8-1 downto 0) := (others => '1');
        variable tuser   : std_logic_vector(s_tuser'range) := (others => '0');
        variable tid     : std_logic_vector(1 to 0);
        variable tdest     : std_logic_vector(1 to 0);
        variable pix_idx : integer;
        variable line_idx : integer;
        
        variable frm_num    : integer := 0; -- frame number
        variable frm_written : boolean := true; -- flag to indicate if frame is written
    begin
        wait until start and rising_edge(clk);
        saved <= false;
        wait for 50 ns;
        wait until rising_edge(clk);

        info("Receiving m_O " & " from UUT...");
        
        pix_idx := 0;
        line_idx := 0;

        while (frm_num < SIM_FRM_NUM) loop
            pop_axi_stream(net, slave_axi_stream, tdata => o, tlast => last, tuser => tuser, tkeep => tkeep, tstrb => tstrobe, tid => tid, tdest => tdest);

            if tuser(0) = '1' then
                if frm_written = false then
                    info("frm " & integer'image(frm_num) & " received, NOT complete, terminated with tuser!");
                    save_csv(m_O, tb_path & csv_o  & integer'image(frm_num) & ".csv");                
                    frm_num := frm_num + 1;
                end if;
                line_idx := 0;
            end if;

            set(m_O, pix_idx*3,   line_idx, to_integer(unsigned(o((0+1)*8-1 downto 0*8))));
            set(m_O, pix_idx*3+1, line_idx, to_integer(unsigned(o((1+1)*8-1 downto 1*8))));
            set(m_O, pix_idx*3+2, line_idx, to_integer(unsigned(o((2+1)*8-1 downto 2*8))));

            if data_width = 16 then
                if tstrobe(1*3) = '1' then
                    set(m_O, pix_idx*3+3, line_idx, to_integer(unsigned(o((3+1)*8-1 downto 8*(3+0)))));
                    set(m_O, pix_idx*3+4, line_idx, to_integer(unsigned(o((3+2)*8-1 downto 8*(3+1)))));
                    set(m_O, pix_idx*3+5, line_idx, to_integer(unsigned(o((3+3)*8-1 downto 8*(3+2)))));
                end if;
            end if;
            
            if last = '1' then
                line_idx := line_idx + 1;
                pix_idx := 0;
                frm_written := false;
            else
                if data_width = 16 and tstrobe(1*3) = '1' then
                    pix_idx := pix_idx + 2;
                else
                    pix_idx := pix_idx + 1;
                end if;
            end if;

            if line_idx =  VER_RES_OUT then
                info("frm " & integer'image(frm_num) & " received!");
                
                save_csv(m_O, tb_path & csv_o  & integer'image(frm_num) & ".csv");                
                frm_num := frm_num + 1;
                line_idx := 0;
                frm_written := true;
            end if;            

        end loop;

        info("m_O read!");

        wait until rising_edge(clk);


        info("m_O saved!");

        wait until rising_edge(clk);
        saved <= true;
  end process;


    uut: entity scale_ip.scale_top 
    generic map(
        AXI_AWIDTH      => 32,
        AXI_DWIDTH      => 32
    )    
    port map(
        aclk                   => clk, 
        aresetn                => resetn, 
        -- register interface
        s_axi_awvalid                =>  s_axi_awvalid,
        s_axi_awready                =>  s_axi_awready,
        s_axi_awaddr                 =>  s_axi_awaddr,
        s_axi_awprot                 =>  s_axi_awprot,
        --
        s_axi_wvalid                 =>  s_axi_wvalid,
        s_axi_wready                 =>  s_axi_wready,
        s_axi_wdata                  =>  s_axi_wdata,
        s_axi_wstrb                  =>  s_axi_wstrb,
        --
        s_axi_bvalid                 =>  s_axi_bvalid,
        s_axi_bready                 =>  s_axi_bready,
        s_axi_bresp                  =>  s_axi_bresp,
        --
        s_axi_arvalid                =>  s_axi_arvalid,
        s_axi_arready                =>  s_axi_arready,
        s_axi_araddr                 =>  s_axi_araddr,
        s_axi_arprot                 =>  s_axi_arprot,
        --
        s_axi_rvalid                 =>  s_axi_rvalid,
        s_axi_rready                 =>  s_axi_rready,
        s_axi_rdata                  =>  s_axi_rdata,
        s_axi_rresp                  =>  s_axi_rresp,
        --
    	axis_tvalid_s_i        => m_tvalid, 
    	axis_tready_s_o        => m_tready, 
    	axis_tdata_s_i         => m_tdata, 
    	axis_tlast_s_i         => m_tlast, 
        axis_tstrobe_s_i       => m_tstrobe, 
    	axis_tuser_s_i         => m_tuser, 
        --
        m_axis_tdata_m_o       => s_tdata, 
        m_axis_tvalid_m_o      => s_tvalid, 
        m_axis_tready_m_i      => s_tready, 
        m_axis_tlast_m_o       => s_tlast, 
        m_axis_tstrobe_m_o     => s_tstrobe, 
        m_axis_tuser_m_o       => s_tuser

    );

    vunit_axism: entity vunit_lib.axi_stream_master
    generic map (
        master => master_axi_stream
    )
    port map (
        aclk   => clk,
        tvalid => m_tvalid,
        tready => m_tready,
        tdata  => m_tdata,
        tlast  => m_tlast,
        tkeep  => m_tkeep,
        tstrb  => m_tstrobe,
        tuser  => m_tuser
    );

    -- Connect AXI Stream Slave to signals
   slave_inst : entity vunit_lib.axi_stream_slave
   generic map (
      slave => slave_axi_stream
   )
    port map (
      aclk   => clk,
      --aresetn => not rst,
      tvalid => s_tvalid,
      tready => s_tready,
      tdata  => s_tdata,
      tuser  => s_tuser,
      tstrb  => s_tstrobe,
      tlast  => s_tlast
    );

    ------------------------------------------------------------------------------------------------
    -- Axi4LiteManager
    ------------------------------------------------------------------------------------------------

    axi_lite_master_inst : entity vunit_lib.axi_lite_master
        generic map (
            bus_handle => AXIL_MASTER_HANDLE -- Pass the handle to this instance
        )
        port map (
            ACLK    => clk,
            AWADDR  => s_axi_awaddr,
            AWVALID => s_axi_awvalid,
            AWREADY => s_axi_awready,
            WDATA   => s_axi_wdata,
            WSTRB   => s_axi_wstrb,
            WVALID  => s_axi_wvalid,
            WREADY  => s_axi_wready,
            BRESP   => s_axi_bresp,
            BVALID  => s_axi_bvalid,
            BREADY  => s_axi_bready,
            ARADDR  => s_axi_araddr,
            ARVALID => s_axi_arvalid,
            ARREADY => s_axi_arready,
            RDATA   => s_axi_rdata,
            RRESP   => s_axi_rresp,
            RVALID  => s_axi_rvalid,
            RREADY  => s_axi_rready
        );

    
    
end architecture beh;
