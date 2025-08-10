from ast import parse
import itertools
import os
import argparse
from pathlib import Path
from poplib import CR
from subprocess import PIPE
import pytest
import random
from typing import List

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, ClockCycles
from cocotb.regression import TestFactory
from cocotb.utils import get_sim_time
from cocotb.queue import Queue
from cocotb.runner import get_runner
from cocotbext.axi import AxiStreamFrame, AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamMonitor

import crcmod

#module name
TOP_MODULE = "tb"

class AXISMonitor:
    def __init__(self, axis_mon: AxiStreamMonitor):
        self.values = Queue[List[int]]()
        self._coro = None
        self.axis_mon = axis_mon
        self._pkt_cnt = 0

    def start(self) -> None:
        """Start monitor"""
        if self._coro is not None:
            raise RuntimeError("Monitor already started")
        self._coro = cocotb.start_soon(self._run())

    def stop(self) -> None:
        """Stop monitor"""
        if self._coro is None:
            raise RuntimeError("Monitor never started")
        self._coro.kill()
        self._coro = None

    def get_pkt_cnt(self) -> int:
        """Get the number of samples"""
        return self._pkt_cnt

    async def _run(self) -> None:
        while True:
            frame = await self.axis_mon.recv()
            self.values.put_nowait(frame.tdata)
            self._pkt_cnt += 1

class TB:
    def __init__(self, dut, crc_sw):
        self.dut = dut
        self.axis_source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "i_data_axis"), dut.clk, dut.rst)
        self.axis_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "o_crc_axis"), dut.clk, dut.rst)
        self.data_mon = AXISMonitor(AxiStreamMonitor(AxiStreamBus.from_prefix(dut, "i_data_axis"), dut.clk, dut.rst))
        self.crc_mon = AXISMonitor(self.axis_sink)
        self.crc_sw = crc_sw

        self._checker = None

    def start(self) -> None:
        """Starts monitors, model, and checker coroutine"""
        if self._checker is not None:
            raise RuntimeError("Monitor already started")
        self.data_mon.start()
        self.crc_mon.start()
        self._checker = cocotb.start_soon(self._check())

    def stop(self) -> None:
        """Stops everything"""
        if self._checker is None:
            raise RuntimeError("Monitor never started")
        self.data_mon.stop()
        self.crc_mon.stop()
        self._checker.kill()
        self._checker = None

    def is_busy(self) -> bool:
        return self.data_mon.get_pkt_cnt() != self.crc_mon.get_pkt_cnt()

    async def _check(self) -> None:
        while True:
            actual_output = await self.crc_mon.values.get()
            actual_input = await self.data_mon.values.get()
            actual_output_val = int.from_bytes(actual_output,'little')
            expected_output_val = self.crc_sw(actual_input)
            assert actual_output_val == expected_output_val, f"\nCRC output mismatch: \ninput: {actual_input.hex()}\noutput:{actual_output.hex()}\nactual: {hex(actual_output_val)}, \nexpected: {hex(expected_output_val)}"

async def unit_test(dut):
    N_BYTES_IN = dut.DWIDTH.value // 8
    crc_name = dut.CRC_NAME.value.decode('utf-8')

    crc_sw = crcmod.predefined.mkCrcFun(crc_name)

    cocotb.start_soon(Clock(dut.clk, 2, units="ns").start())
    tb = TB(dut, crc_sw)

    dut._log.info("Initialize and reset model")

    dut.rst.value = 0
    await ClockCycles(dut.clk, 20)
    dut.rst.value = 1
    await ClockCycles(dut.clk, 20)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

    #out of reset
    tb.start()
    dut._log.info("Test Started")

    #maximum packet size is 4.5 flits of the bus width
    max_pkt_size = int(N_BYTES_IN*4.5)

    #sweep packet size from 1 byte to 4.5 flits of the wider bus
    for size in range(1,max_pkt_size+1):
        #3 packets for each size
        for _ in range(3):
            #generate tkeep for every flit
            payload = random.randbytes(size)
            frame = AxiStreamFrame(tdata=payload)
            await tb.axis_source.send(frame)
    while get_sim_time(units="us") < 100:
        await RisingEdge(dut.clk)
        if not tb.is_busy():
            break
    await Timer(100, units="ns")
    dut._log.info("Test Finished")

@pytest.mark.parametrize("DWIDTH", [32,128,512,768])
@pytest.mark.parametrize("PIPE_LVL", [0,1])
@pytest.mark.parametrize("REV_PIPE_EN_ONEHOT", [0,0xffffffff])
@pytest.mark.parametrize("CRC_NAME", [crc['name'] for crc in crcmod.predefined._crc_definitions])
def test_runner(DWIDTH, PIPE_LVL, REV_PIPE_EN_ONEHOT, CRC_NAME):
    sim = os.getenv("SIM", "verilator")

    sim_path = Path(__file__).resolve().parent
    proj_path = Path(__file__).resolve().parent.parent / "rtl"
    module_name = Path(__file__).stem

    verilog_sources = list(proj_path.rglob("*.sv")) + list(proj_path.rglob("*.v")) + [sim_path / "tb.sv"]

    CRC_NAME_STR = f'"{CRC_NAME}"'

    CRC_CODE = crcmod.predefined._get_definition_by_name(CRC_NAME)
    CRC_POLY = CRC_CODE['poly']
    CRC_WIDTH = CRC_POLY.bit_length() - 1

    CRC_POLY = CRC_POLY & ((1 << CRC_WIDTH) - 1)
    CRC_POLY_STR = f"{CRC_WIDTH}'d{CRC_POLY}"

    CRC_XOR_OUT = CRC_CODE['xor_out']
    CRC_XOR_OUT_STR = f"{CRC_WIDTH}'d{CRC_XOR_OUT}"
    CRC_INIT = CRC_CODE['init'] ^ CRC_XOR_OUT
    CRC_INIT_STR = f"{CRC_WIDTH}'d{CRC_INIT}"
    CRC_REVERSE = 1 if CRC_CODE['reverse'] else 0

    parameters = {
        "DWIDTH": DWIDTH,
        "PIPE_LVL": PIPE_LVL,
        "REV_PIPE_EN_ONEHOT": REV_PIPE_EN_ONEHOT,
        "CRC_NAME": CRC_NAME_STR,
        "CRC_WIDTH": CRC_WIDTH,
        "CRC_POLY": CRC_POLY_STR,
        "INIT" : CRC_INIT_STR,
        "XOR_OUT": CRC_XOR_OUT_STR,
        "REFIN": CRC_REVERSE,
        "REFOUT": CRC_REVERSE
    }

    runner = get_runner(sim)

    runner.build(
        hdl_toplevel=TOP_MODULE,
        verilog_sources=verilog_sources,
        includes=[proj_path],
        parameters=parameters,
        waves=True,
        build_args=["-Wno-WIDTHCONCAT","-Wno-WIDTHEXPAND","-Wno-UNOPTFLAT","+1800-2012ext+sv"],
        build_dir=f"sim_{CRC_NAME}_{DWIDTH}_{PIPE_LVL}_{REV_PIPE_EN_ONEHOT}",
        always=True
    )

    runner.test(
        hdl_toplevel=TOP_MODULE,
        hdl_toplevel_lang="verilog",
        waves=True,
        test_module=module_name
    )

if cocotb.SIM_NAME:
    factory = TestFactory(unit_test)
    factory.generate_tests()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run Tbps CRC tests")
    parser.add_argument("--DWIDTH", type=int, default=32, help="Input AXIS data width in bytes")
    parser.add_argument("--PIPE_LVL", type=int, default=0, help="Pipeline level")
    parser.add_argument("--REV_PIPE_EN_ONEHOT", type=int, default=0, help="Reverse pipeline enable one-hot encoding")
    parser.add_argument("--CRC_NAME", type=str, default="crc-32", help="CRC polynomial name")
    args = parser.parse_args()

    test_runner(args.DWIDTH,args.PIPE_LVL,args.REV_PIPE_EN_ONEHOT, args.CRC_NAME)