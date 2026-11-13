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
-- File: tb_scale_reg.vhd
-- Description: AXI4-Lite protocol regression tests for scale_reg.
--              Drives the AXI channels directly (no BFM) so that channel
--              ordering and back-pressure can be controlled per test:
--              AW/W in either order, stalled RREADY, unmapped addresses,
--              back-to-back writes and byte strobes.
--              IRQ_FLAG write-1-to-clear is not covered: irq_flags has no
--              source inside scale_reg yet, so no flag can be raised.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

library scale_ip;

entity tb_scale_reg is
    generic (runner_cfg : string);
end entity;

architecture sim of tb_scale_reg is
    constant CLK_PERIOD : time := 10 ns;
    constant TIMEOUT    : natural := 50;   -- cycles before a handshake is declared hung

    -- register map
    constant REG_SC_INFO  : natural := 16#00#;
    constant REG_SC_HCOEF : natural := 16#08#;
    constant REG_SC_VCOEF : natural := 16#0C#;
    constant REG_SC_VRES  : natural := 16#10#;
    constant REG_UNMAPPED : natural := 16#1C#;

    -- reset values
    constant RST_SC_COEF  : std_logic_vector(31 downto 0) := x"00400000"; -- SCALE_CNT_ONE
    constant RST_SC_VRES  : std_logic_vector(31 downto 0) := x"00000780"; -- 1920

    signal aclk    : std_logic := '0';
    signal aresetn : std_logic := '0';
    signal awvalid, awready : std_logic := '0';
    signal awaddr  : std_logic_vector(31 downto 0) := (others => '0');
    signal wvalid, wready   : std_logic := '0';
    signal wdata   : std_logic_vector(31 downto 0) := (others => '0');
    signal wstrb   : std_logic_vector(3 downto 0) := (others => '1');
    signal bvalid, bready   : std_logic := '0';
    signal bresp   : std_logic_vector(1 downto 0);
    signal arvalid, arready : std_logic := '0';
    signal araddr  : std_logic_vector(31 downto 0) := (others => '0');
    signal rvalid, rready   : std_logic := '0';
    signal rdata   : std_logic_vector(31 downto 0);
    signal rresp   : std_logic_vector(1 downto 0);
    signal irq     : std_logic;
    signal scale_hor, scale_ver : std_logic_vector(31 downto 0);
    signal res_ver : std_logic_vector(15 downto 0);
begin
    aclk <= not aclk after CLK_PERIOD / 2;

    dut: entity scale_ip.scale_reg
        generic map (
            AXI_AWIDTH => 32,
            AXI_DWIDTH => 32
        )
        port map (
            aclk => aclk, aresetn => aresetn,
            awvalid => awvalid, awready => awready, awaddr => awaddr, awprot => "000",
            wvalid => wvalid, wready => wready, wdata => wdata, wstrb => wstrb,
            bvalid => bvalid, bready => bready, bresp => bresp,
            arvalid => arvalid, arready => arready, araddr => araddr, arprot => "000",
            rvalid => rvalid, rready => rready, rdata => rdata, rresp => rresp,
            irq => irq,
            scale_hor => scale_hor, scale_ver => scale_ver, res_ver => res_ver
        );

    test_runner_watchdog(runner, 100 us);

    main: process
        variable d : std_logic_vector(31 downto 0);

        procedure tick(n : natural := 1) is
        begin
            for i in 1 to n loop
                wait until rising_edge(aclk);
            end loop;
        end procedure;

        -- aw_delay / w_delay: cycles before each channel is driven valid,
        -- so either channel can be made to arrive first
        procedure axi_write(addr     : natural;
                            data     : std_logic_vector(31 downto 0);
                            aw_delay : natural := 0;
                            w_delay  : natural := 0;
                            strb     : std_logic_vector(3 downto 0) := "1111") is
            variable aw_ok, w_ok : boolean := false;
            variable t : natural := 0;
        begin
            awaddr <= std_logic_vector(to_unsigned(addr, 32));
            wdata  <= data;
            wstrb  <= strb;
            bready <= '1';
            loop
                awvalid <= '1' when (t >= aw_delay and not aw_ok) else '0';
                wvalid  <= '1' when (t >= w_delay  and not w_ok)  else '0';
                tick;
                if awvalid = '1' and awready = '1' then aw_ok := true; end if;
                if wvalid  = '1' and wready  = '1' then w_ok  := true; end if;
                if bvalid = '1' then
                    check(aw_ok and w_ok, "BVALID before both AW and W were accepted");
                    check_equal(bresp, std_logic_vector'("00"), "BRESP");
                    exit;
                end if;
                t := t + 1;
                check(t <= TIMEOUT, "write to 0x" & to_hstring(to_unsigned(addr, 8)) &
                                    " hung (aw_ok=" & boolean'image(aw_ok) &
                                    ", w_ok=" & boolean'image(w_ok) & ")");
            end loop;
            awvalid <= '0';
            wvalid  <= '0';
            bready  <= '0';
            tick;
        end procedure;

        procedure axi_read(addr : natural; data : out std_logic_vector(31 downto 0)) is
            variable t : natural := 0;
        begin
            araddr  <= std_logic_vector(to_unsigned(addr, 32));
            arvalid <= '1';
            loop
                tick;
                exit when arready = '1';
                t := t + 1;
                check(t <= TIMEOUT, "AR handshake hung");
            end loop;
            arvalid <= '0';
            t := 0;
            while rvalid /= '1' loop
                tick;
                t := t + 1;
                check(t <= TIMEOUT, "RVALID never asserted");
            end loop;
            data := rdata;
            check_equal(rresp, std_logic_vector'("00"), "RRESP");
            rready <= '1';
            tick;
            rready <= '0';
        end procedure;

        procedure check_reg(addr : natural; expected : std_logic_vector(31 downto 0)) is
            variable v : std_logic_vector(31 downto 0);
        begin
            axi_read(addr, v);
            check_equal(v, expected, "register 0x" & to_hstring(to_unsigned(addr, 8)));
        end procedure;

    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop
            aresetn <= '0';
            tick(3);
            aresetn <= '1';
            tick(2);

            if run("reset_values") then
                check_reg(REG_SC_HCOEF, RST_SC_COEF);
                check_reg(REG_SC_VCOEF, RST_SC_COEF);
                check_reg(REG_SC_VRES,  RST_SC_VRES);
                check_equal(scale_hor, RST_SC_COEF, "scale_hor output");
                check_equal(scale_ver, RST_SC_COEF, "scale_ver output");
                check_equal(res_ver, RST_SC_VRES(15 downto 0), "res_ver output");

            elsif run("aw_and_w_together") then
                axi_write(REG_SC_HCOEF, x"00011111");
                axi_write(REG_SC_VRES,  x"00000222");
                check_reg(REG_SC_HCOEF, x"00011111");
                check_reg(REG_SC_VRES,  x"00000222");
                check_equal(scale_hor, std_logic_vector'(x"00011111"), "scale_hor output");
                check_equal(res_ver, std_logic_vector'(x"0222"), "res_ver output");

            elsif run("aw_before_w") then
                -- previous write leaves the latched write address at HCOEF;
                -- the late-W write must still land in VRES
                axi_write(REG_SC_HCOEF, x"00011111");
                axi_write(REG_SC_VRES,  x"00000333", aw_delay => 0, w_delay => 3);
                check_reg(REG_SC_VRES,  x"00000333");
                check_reg(REG_SC_HCOEF, x"00011111");

            elsif run("w_before_aw") then
                axi_write(REG_SC_VCOEF, x"00044444", aw_delay => 3, w_delay => 0);
                check_reg(REG_SC_VCOEF, x"00044444");

            elsif run("rdata_stable_during_rready_stall") then
                axi_write(REG_SC_HCOEF, x"0000AAAA");
                axi_write(REG_SC_VCOEF, x"0000BBBB");
                araddr  <= std_logic_vector(to_unsigned(REG_SC_HCOEF, 32));
                arvalid <= '1';
                loop
                    tick;
                    exit when arready = '1';
                end loop;
                -- master immediately offers the next read address (legal)
                araddr <= std_logic_vector(to_unsigned(REG_SC_VCOEF, 32));
                while rvalid /= '1' loop
                    tick;
                end loop;
                d := rdata;
                check_equal(d, std_logic_vector'(x"0000AAAA"), "first read data");
                for i in 1 to 5 loop
                    tick;
                    check_equal(rvalid, '1', "RVALID dropped without RREADY");
                    check_equal(rdata, d, "RDATA changed while RVALID=1 and RREADY=0");
                end loop;
                rready <= '1';
                tick;                                   -- R handshake for HCOEF
                loop                                    -- complete the VCOEF read
                    exit when rvalid = '1' and arvalid = '0';
                    if arready = '1' and arvalid = '1' then
                        arvalid <= '0';
                    end if;
                    tick;
                end loop;
                check_equal(rdata, std_logic_vector'(x"0000BBBB"), "second read data");
                tick;
                rready <= '0';

            elsif run("unmapped_address") then
                axi_write(REG_UNMAPPED, x"12345678");
                check_reg(REG_UNMAPPED, x"00000000");
                check_reg(REG_SC_HCOEF, RST_SC_COEF);
                check_reg(REG_SC_VCOEF, RST_SC_COEF);
                check_reg(REG_SC_VRES,  RST_SC_VRES);

            elsif run("read_only_register") then
                d := (others => '0');
                axi_read(REG_SC_INFO, d);
                axi_write(REG_SC_INFO, not d);
                check_reg(REG_SC_INFO, d);

            elsif run("back_to_back_writes_mixed_order") then
                for i in 0 to 3 loop
                    axi_write(REG_SC_VRES, std_logic_vector(to_unsigned(16#100# + i, 32)),
                              aw_delay => i mod 2, w_delay => (i + 1) mod 2);
                    check_reg(REG_SC_VRES, std_logic_vector(to_unsigned(16#100# + i, 32)));
                end loop;

            elsif run("byte_strobes") then
                axi_write(REG_SC_VRES, x"AABBCCDD");
                axi_write(REG_SC_VRES, x"11223344", strb => "0010");
                check_reg(REG_SC_VRES, x"AABB33DD");

            end if;
        end loop;

        test_runner_cleanup(runner);
    end process;
end architecture;
