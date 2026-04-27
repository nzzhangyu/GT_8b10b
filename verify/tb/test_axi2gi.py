import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge
from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamFrame
import logging
import random
import os

def _set_lane_delay(dut, lane_idx, delay):
    width = len(dut.inj_skew_lane)
    lane_num = width // 6
    assert lane_idx < lane_num, f"Lane {lane_idx} out of range, lane_num={lane_num}"
    cur = int(dut.inj_skew_lane.value)
    mask = ((1 << 6) - 1) << (lane_idx * 6)
    nxt = (cur & ~mask) | ((delay & 0x3F) << (lane_idx * 6))
    dut.inj_skew_lane.value = nxt

async def reset_dut(dut):
    dut.sys_reset.setimmediatevalue(1)
    dut.inj_skew_lane.setimmediatevalue(0)
    dut.inj_bit_flip.setimmediatevalue(0)
    dut.inj_link_drop.setimmediatevalue(0)

    for _ in range(20):
        await dut.sys_clk.rising_edge
    dut.sys_reset.value = 0

    for _ in range(50):
        await dut.sys_clk.rising_edge

@cocotb.test()
async def test_full_link_with_skew(dut):

    # GT CLOCK: 156.25 MHz
    cocotb.start_soon(Clock(dut.sys_clk, 6.4, unit="ns").start())

    # Bind AXI-Stream VIPs (Source for TX, Sink for RX)
    axis_source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axi"), dut.sys_clk, dut.sys_reset)
    axis_sink   = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axi"), dut.sys_clk, dut.sys_reset)

    axis_source.log.setLevel(logging.WARNING)
    axis_sink.log.setLevel(logging.WARNING)

    # System Reset
    dut._log.info("Resetting DUT...")
    await reset_dut(dut)

    """
    Test 1: Lane Skew injection and full-duplex AXI packet TX/RX verification.
    """
    dut._log.info("=== SCENARIO A: Lane Skew Alignment & Normal Traffic ===")
    # Inject extreme lane skew on first two lanes
    _set_lane_delay(dut, 0, 5)
    if len(dut.inj_bit_flip) > 1:
        _set_lane_delay(dut, 1, 28)
    dut._log.info("Injected Lane Skew: Lane0=5, Lane1=28. Waiting for RX alignment...")

    # Wait for RX lane deskew and alignment
    align_timeout = 0
    while dut.lane_aligned.value != 1:
        await dut.sys_clk.rising_edge
        align_timeout += 1
        if align_timeout > 10000:
            assert False, "Timeout: RX Failed to align lanes!"
    
    dut._log.info(f"RX Lane Aligned Successfully after {align_timeout} cycles!")

    # Send 10 random-length AXI packets
    num_packets = 10
    sent_pkts = []

    for i in range(num_packets):
        length = random.randint(8, 64)*8    # Packet length: 64 to 512 bytes
        payload = bytearray(os.urandom(length))        # Generate random byte stream
        sent_pkts.append(payload)
        # Drive data via AXI VIP (handles tvalid/tready/tlast automatically)
        await axis_source.send(payload)
        
        hex_preview = payload.hex().upper()[:16]
        dut._log.info(f"Sent Packet {i}, length: {length} bytes")

    # Receive and verify data
    for i in range(num_packets):
        rx_frame = await axis_sink.recv()
        rx_payload = rx_frame.tdata

        assert rx_payload == sent_pkts[i], f"Data Mismatch for Packet {i}!"
        dut._log.info(f"Received and verified Packet {i} successfully!")


    await Timer(500, unit="ns")

    """
    Test 2: Inject physical layer bit flips and validate CRC checksum error detection.
    """

    dut._log.info("=== SCENARIO B: Bit Flip Injection & CRC Error Detection ===")
    
    err_payload = bytearray(os.urandom(256))

    # # Define a background coroutine to "sabotage" data during transmission
    async def inject_error_later():
        await Timer(1000, unit="ns")        # Wait for the packet to be mid-transmission
        dut.inj_bit_flip.value = 0x1        # Force a bit flip on Lane 0
        await dut.sys_clk.rising_edge       # Hold the error for one clock cycle
        dut.inj_bit_flip.value = 0          # Clear the error injection
        dut._log.warning("Injected Bit Flip Error into Lane 0")

    # Launch the background error injection task
    cocotb.start_soon(inject_error_later())

    # Send the data packet via AXI VIP
    await axis_source.send(err_payload)

    # Monitor the DUT's receiver-side CRC error flag
    crc_error_detected = False
    for _ in range(2000):
        await dut.sys_clk.rising_edge
        if dut.rx_crc_error.value == 1:
            crc_error_detected = True
            dut._log.info("SUCCESS: RX CRC Module caught the bit flip!")
            break

    assert crc_error_detected, "FAIL: RX failed to detect the injected bit flip!"

    await Timer(1000, unit="ns")
    dut._log.info("All test scenarios passed completely!")