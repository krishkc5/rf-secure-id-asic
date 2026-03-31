import os
import subprocess
import sys
from pathlib import Path

from cocotb_test.simulator import run


def _base_verilog_sources(repo_root: Path) -> list[str]:
    rtl_dir = repo_root / "rtl"

    return [
        str(rtl_dir / "rf_secure_id_packet_rx.sv"),
        str(rtl_dir / "rf_secure_id_packet_parser.sv"),
        str(rtl_dir / "rf_secure_id_crc16_checker.sv"),
        str(rtl_dir / "rf_secure_id_aes_decrypt.sv"),
        str(rtl_dir / "rf_secure_id_plaintext_validator.sv"),
        str(rtl_dir / "rf_secure_id_cam.sv"),
        str(rtl_dir / "rf_secure_id_timeout_monitor.sv"),
        str(rtl_dir / "rf_secure_id_classifier.sv"),
        str(rtl_dir / "rf_secure_id_digital.sv"),
    ]


def _rtl_include_dirs(repo_root: Path) -> list[str]:
    return [str(repo_root / "rtl")]


def _prepare_env() -> tuple[Path, Path]:
    repo_root = Path(__file__).resolve().parents[1]
    tb_dir = repo_root / "tb"
    python_bin_dir = Path(sys.executable).resolve().parent

    os.environ["PATH"] = f"{python_bin_dir}{os.pathsep}{os.environ['PATH']}"

    return repo_root, tb_dir


def _export_synth_netlist(repo_root: Path) -> Path:
    synth_netlist = repo_root / "synth.v"

    subprocess.run(
        [
            "yosys",
            "-p",
            (
                "read_verilog -sv rtl/*.sv; "
                "hierarchy -top rf_secure_id_digital; "
                "proc; opt; write_verilog synth.v"
            ),
        ],
        check=True,
        cwd=repo_root,
    )

    return synth_netlist


def test_rf_secure_id_cocotb_default() -> None:
    repo_root, tb_dir = _prepare_env()

    run(
        simulator="verilator",
        python_search=[str(tb_dir)],
        includes=_rtl_include_dirs(repo_root),
        verilog_sources=_base_verilog_sources(repo_root),
        toplevel="rf_secure_id_digital",
        module="test_rf_secure_id",
        defines=["RF_SECURE_ID_SIMONLY"],
        extra_args=["--timing"],
        force_compile=True,
        sim_build=str(repo_root / "sim_build" / "verilator_default"),
    )


def test_rf_secure_id_cocotb_forced_timeout() -> None:
    repo_root, tb_dir = _prepare_env()

    verilog_sources = _base_verilog_sources(repo_root) + [
        str(tb_dir / "rf_secure_id_timeout4_top.sv"),
    ]

    run(
        simulator="verilator",
        python_search=[str(tb_dir)],
        includes=_rtl_include_dirs(repo_root),
        verilog_sources=verilog_sources,
        toplevel="rf_secure_id_timeout4_top",
        module="test_rf_secure_id",
        defines=["RF_SECURE_ID_SIMONLY"],
        extra_args=["--timing"],
        force_compile=True,
        sim_build=str(repo_root / "sim_build" / "verilator_timeout4"),
    )


def test_rf_secure_id_cocotb_synth_netlist_smoke() -> None:
    repo_root, tb_dir = _prepare_env()
    synth_netlist = _export_synth_netlist(repo_root)

    extra_env = os.environ.copy()
    extra_env["RF_SECURE_ID_NETLIST_SMOKE"] = "1"

    run(
        simulator="verilator",
        python_search=[str(tb_dir)],
        includes=[],
        verilog_sources=[str(synth_netlist)],
        toplevel="rf_secure_id_digital",
        module="test_rf_secure_id",
        extra_env=extra_env,
        extra_args=[
            "--timing",
            "-Wno-PINMISSING",
            "-Wno-WIDTHTRUNC",
            "-Wno-WIDTHEXPAND",
            "-Wno-CASEOVERLAP",
        ],
        force_compile=True,
        sim_build=str(repo_root / "sim_build" / "verilator_synth_netlist"),
    )
