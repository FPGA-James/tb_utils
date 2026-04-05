-- =============================================================================
-- tb_axis_vip_example.vhd
-- Example testbench showing how to instantiate the monitor and sink VIPs
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.axi_stream_vip_pkg.all;

entity tb_axis_vip_example is
end entity tb_axis_vip_example;

architecture sim of tb_axis_vip_example is

  constant C_CLK_PERIOD  : time     := 10 ns;
  constant C_DATA_BYTES  : positive := 4;

  signal clk     : std_logic := '0';
  signal resetn  : std_logic := '0';

  -- AXI-Stream master signals
  signal m_tvalid : std_logic := '0';
  signal m_tready : std_logic;
  signal m_tdata  : std_logic_vector(C_DATA_BYTES * 8 - 1 downto 0) := (others => '0');
  signal m_tkeep  : std_logic_vector(C_DATA_BYTES - 1 downto 0)     := (others => '1');
  signal m_tstrb  : std_logic_vector(C_DATA_BYTES - 1 downto 0)     := (others => '1');
  signal m_tlast  : std_logic := '0';

begin

  -- Clock generation
  clk <= not clk after C_CLK_PERIOD / 2;

  -- Reset release
  p_reset : process
  begin
    resetn <= '0';
    wait for C_CLK_PERIOD * 5;
    resetn <= '1';
    wait;
  end process;

  -- ===========================================================================
  -- Passive monitor — taps the bus without affecting it
  -- ===========================================================================
  u_monitor : entity work.axi_stream_monitor
    generic map (
      G_DATA_BYTES => C_DATA_BYTES,
      G_NAME       => "DUT_MON"
    )
    port map (
      aclk    => clk,
      aresetn => resetn,
      tvalid  => m_tvalid,
      tready  => m_tready,
      tdata   => m_tdata,
      tkeep   => m_tkeep,
      tstrb   => m_tstrb,
      tlast   => m_tlast
    );

  -- ===========================================================================
  -- Active sink — drives TREADY, captures beats to memory and console
  -- ===========================================================================
  u_sink : entity work.axi_stream_sink
    generic map (
      G_DATA_BYTES    => C_DATA_BYTES,
      G_TREADY_ALWAYS => false,   -- apply random backpressure
      G_READY_PROB    => 0.75,    -- TREADY asserted ~75% of cycles
      G_NAME          => "DUT_SINK"
    )
    port map (
      aclk    => clk,
      aresetn => resetn,
      tvalid  => m_tvalid,
      tready  => m_tready,
      tdata   => m_tdata,
      tkeep   => m_tkeep,
      tstrb   => m_tstrb,
      tlast   => m_tlast
    );

  -- ===========================================================================
  -- Simple stimulus: send two packets
  -- ===========================================================================
  p_stimulus : process
    procedure send_beat (
      data  : std_logic_vector(C_DATA_BYTES * 8 - 1 downto 0);
      keep  : std_logic_vector(C_DATA_BYTES - 1 downto 0);
      last  : std_logic
    ) is
    begin
      m_tdata  <= data;
      m_tkeep  <= keep;
      m_tstrb  <= keep;
      m_tlast  <= last;
      m_tvalid <= '1';
      -- Wait for handshake
      loop
        wait until rising_edge(clk);
        exit when m_tready = '1';
      end loop;
      m_tvalid <= '0';
    end procedure;
  begin
    wait until resetn = '1';
    wait until rising_edge(clk);

    -- Packet 0: 3 full beats
    send_beat(x"DEADBEEF", x"F", '0');
    send_beat(x"CAFEF00D", x"F", '0');
    send_beat(x"01234567", x"F", '1');

    wait for C_CLK_PERIOD * 4;

    -- Packet 1: 2 beats, last beat has 3 valid bytes (TKEEP=0111)
    send_beat(x"AABBCCDD", x"F", '0');
    send_beat(x"EEFF0000", x"7", '1');  -- top byte null

    wait for C_CLK_PERIOD * 10;

    report "Simulation complete" severity note;
    std.env.stop;
  end process;

end architecture sim;
