import os
import sys
from pathlib import Path

from cocotb_test.simulator import run


def test_rf_secure_id_cocotb() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    rtl_dir = repo_root / "rtl"
    tb_dir = repo_root / "tb"
    python_bin_dir = Path(sys.executable).resolve().parent

    os.environ["PATH"] = f"{python_bin_dir}{os.pathsep}{os.environ['PATH']}"

    verilog_sources = [
        rtl_dir / "packet_rx.sv",
        rtl_dir / "packet_parser.sv",
        rtl_dir / "crc16_checker.sv",
        rtl_dir / "aes_decrypt.sv",
        rtl_dir / "plaintext_validator.sv",
        rtl_dir / "cam.sv",
        rtl_dir / "classifier.sv",
        rtl_dir / "rf_secure_id_digital.sv",
    ]

    run(
        simulator="verilator",
        python_search=[str(tb_dir)],
        verilog_sources=[str(path) for path in verilog_sources],
        toplevel="rf_secure_id_digital",
        module="test_rf_secure_id",
        extra_args=["--timing"],
        force_compile=True,
        sim_build=str(repo_root / "sim_build" / "verilator"),
    )
