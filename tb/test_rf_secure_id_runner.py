import os
import sys
from pathlib import Path

from cocotb_test.simulator import run


def _base_verilog_sources(repo_root: Path) -> list[str]:
    rtl_dir = repo_root / "rtl"

    return [
        str(rtl_dir / "packet_rx.sv"),
        str(rtl_dir / "packet_parser.sv"),
        str(rtl_dir / "crc16_checker.sv"),
        str(rtl_dir / "aes_decrypt.sv"),
        str(rtl_dir / "plaintext_validator.sv"),
        str(rtl_dir / "cam.sv"),
        str(rtl_dir / "timeout_monitor.sv"),
        str(rtl_dir / "classifier.sv"),
        str(rtl_dir / "rf_secure_id_digital.sv"),
    ]


def _prepare_env() -> tuple[Path, Path]:
    repo_root = Path(__file__).resolve().parents[1]
    tb_dir = repo_root / "tb"
    python_bin_dir = Path(sys.executable).resolve().parent

    os.environ["PATH"] = f"{python_bin_dir}{os.pathsep}{os.environ['PATH']}"

    return repo_root, tb_dir


def test_rf_secure_id_cocotb_default() -> None:
    repo_root, tb_dir = _prepare_env()

    run(
        simulator="verilator",
        python_search=[str(tb_dir)],
        verilog_sources=_base_verilog_sources(repo_root),
        toplevel="rf_secure_id_digital",
        module="test_rf_secure_id",
        extra_args=["--timing"],
        force_compile=True,
        sim_build=str(repo_root / "sim_build" / "verilator_default"),
    )


def test_rf_secure_id_cocotb_forced_timeout() -> None:
    repo_root, tb_dir = _prepare_env()

    verilog_sources = _base_verilog_sources(repo_root) + [
        str(tb_dir / "rf_secure_id_digital_timeout4.sv"),
    ]

    run(
        simulator="verilator",
        python_search=[str(tb_dir)],
        verilog_sources=verilog_sources,
        toplevel="rf_secure_id_digital_timeout4",
        module="test_rf_secure_id",
        extra_args=["--timing"],
        force_compile=True,
        sim_build=str(repo_root / "sim_build" / "verilator_timeout4"),
    )
