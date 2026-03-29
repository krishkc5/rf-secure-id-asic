import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge, Timer

PREAMBLE = 0xA5
CRC_POLY = 0x1021
CLK_PERIOD_NS = 10
PACKET_WIDTH = 160

FIXED_KEY = 0x000102030405060708090A0B0C0D0E0F
ROUND_KEYS = (
    FIXED_KEY,
    0xD6AA74FDD2AF72FADAA678F1D6AB76FE,
    0xB692CF0B643DBDF1BE9BC5006830B3FE,
    0xB6FF744ED2C2C9BF6C590CBF0469BF41,
    0x47F7F7BC95353E03F96C32BCFD058DFD,
    0x3CAAA3E8A99F9DEB50F3AF57ADF622AA,
    0x5E390F7DF7A69296A7553DC10AA31F6B,
    0x14F9701AE35FE28C440ADF4D4EA9C026,
    0x47438735A41C65B9E016BAF4AEBF7AD2,
    0x549932D1F08557681093ED9CBE2C974E,
    0x13111D7FE3944A17F307A78B4D2B30C5,
)

SBOX = (
    0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5, 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
    0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0, 0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
    0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC, 0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
    0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A, 0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
    0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0, 0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
    0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B, 0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
    0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85, 0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
    0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5, 0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
    0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17, 0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
    0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88, 0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
    0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C, 0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
    0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9, 0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
    0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6, 0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
    0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E, 0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
    0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94, 0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
    0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68, 0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16,
)

PLAIN_MAGIC = 0xC35A
TEST_PACKET_TYPE = 0x01
AUTHORIZED_ID = 0x1234
UNAUTHORIZED_ID = 0x2222
AUTHORIZED_IDS = (0x1234, 0x5678, 0x9ABC, 0xDEF0)

AES_KAT_PLAINTEXT = 0x00112233445566778899AABBCCDDEEFF
AES_KAT_CIPHERTEXT = 0x69C4E0D86A7B0430D8CDB78070B4C55A

CLASSIFY_LATENCY = 16
DEFAULT_TIMEOUT_CYCLES = 32
DEFAULT_UNRESPONSIVE_LATENCY = DEFAULT_TIMEOUT_CYCLES + 4
FORCED_TIMEOUT_CYCLES = 4
FORCED_TIMEOUT_LATENCY = FORCED_TIMEOUT_CYCLES + 4
NO_CLASSIFY_WINDOW = CLASSIFY_LATENCY + 1
WRONG_PREAMBLE_NO_CLASSIFY_WINDOW = PACKET_WIDTH + CLASSIFY_LATENCY + 4
BACK_TO_BACK_WINDOW = (2 * PACKET_WIDTH) + (2 * CLASSIFY_LATENCY) + 8
RANDOM_STRESS_SEED = 0xC35A1234
RANDOM_STRESS_PACKETS = 128


def calc_crc16(packet_type: int, ciphertext: int) -> int:
    crc = 0x0000
    data = ((packet_type & 0xFF) << 128) | (ciphertext & ((1 << 128) - 1))

    for bit_idx in range(135, -1, -1):
        data_bit = (data >> bit_idx) & 0x1
        feedback = ((crc >> 15) & 0x1) ^ data_bit
        crc = ((crc << 1) & 0xFFFF)

        if feedback:
            crc ^= CRC_POLY

    return crc


def build_plaintext(id_in: int, plain_magic: int = PLAIN_MAGIC, reserved: int = 0) -> int:
    return (
        ((plain_magic & 0xFFFF) << 112)
        | ((id_in & 0xFFFF) << 96)
        | (reserved & ((1 << 96) - 1))
    )


def split_state(state: int) -> list[int]:
    return [(state >> shift) & 0xFF for shift in range(120, -1, -8)]


def pack_state(byte_lanes: list[int]) -> int:
    state = 0

    for byte_lane in byte_lanes:
        state = (state << 8) | (byte_lane & 0xFF)

    return state


def gf_mul8(a: int, b: int) -> int:
    multiplicand = a & 0xFF
    multiplier = b & 0xFF
    product = 0

    for _ in range(8):
        if multiplier & 0x1:
            product ^= multiplicand

        if multiplicand & 0x80:
            multiplicand = ((multiplicand << 1) & 0xFF) ^ 0x1B
        else:
            multiplicand = (multiplicand << 1) & 0xFF

        multiplier >>= 1

    return product


def sub_bytes(state: int) -> int:
    return pack_state([SBOX[byte_lane] for byte_lane in split_state(state)])


def shift_rows(state: int) -> int:
    byte_lane = split_state(state)

    shifted = [
        byte_lane[0],  byte_lane[5],  byte_lane[10], byte_lane[15],
        byte_lane[4],  byte_lane[9],  byte_lane[14], byte_lane[3],
        byte_lane[8],  byte_lane[13], byte_lane[2],  byte_lane[7],
        byte_lane[12], byte_lane[1],  byte_lane[6],  byte_lane[11],
    ]

    return pack_state(shifted)


def mix_columns(state: int) -> int:
    byte_lane = split_state(state)
    mixed = [0] * 16

    for col_idx in range(4):
        base_idx = col_idx * 4
        a0 = byte_lane[base_idx + 0]
        a1 = byte_lane[base_idx + 1]
        a2 = byte_lane[base_idx + 2]
        a3 = byte_lane[base_idx + 3]

        mixed[base_idx + 0] = gf_mul8(a0, 0x02) ^ gf_mul8(a1, 0x03) ^ a2 ^ a3
        mixed[base_idx + 1] = a0 ^ gf_mul8(a1, 0x02) ^ gf_mul8(a2, 0x03) ^ a3
        mixed[base_idx + 2] = a0 ^ a1 ^ gf_mul8(a2, 0x02) ^ gf_mul8(a3, 0x03)
        mixed[base_idx + 3] = gf_mul8(a0, 0x03) ^ a1 ^ a2 ^ gf_mul8(a3, 0x02)

    return pack_state(mixed)


def add_round_key(state: int, round_key: int) -> int:
    return state ^ round_key


def aes128_encrypt_block(plaintext: int) -> int:
    state = add_round_key(plaintext, ROUND_KEYS[0])

    for round_idx in range(1, 10):
        state = sub_bytes(state)
        state = shift_rows(state)
        state = mix_columns(state)
        state = add_round_key(state, ROUND_KEYS[round_idx])

    state = sub_bytes(state)
    state = shift_rows(state)
    state = add_round_key(state, ROUND_KEYS[10])

    return state


def verify_aes_helper() -> None:
    assert (
        aes128_encrypt_block(AES_KAT_PLAINTEXT) == AES_KAT_CIPHERTEXT
    ), "AES-128 Python helper failed known-answer test"


def build_packet(
    packet_type: int,
    ciphertext: int,
    corrupt_crc: bool = False,
    preamble: int = PREAMBLE,
) -> int:
    crc = calc_crc16(packet_type, ciphertext)

    if corrupt_crc:
        crc ^= 0x0001

    return (
        ((preamble & 0xFF) << 152)
        | ((packet_type & 0xFF) << 144)
        | ((ciphertext & ((1 << 128) - 1)) << 16)
        | (crc & 0xFFFF)
    )


async def send_serial_bits(
    dut,
    value: int,
    msb_idx: int,
    lsb_idx: int,
    idle_after: bool = True,
) -> None:
    for bit_idx in range(msb_idx, lsb_idx - 1, -1):
        await FallingEdge(dut.clk)
        dut.serial_bit.value = (value >> bit_idx) & 0x1
        await RisingEdge(dut.clk)

    if idle_after:
        await FallingEdge(dut.clk)
        dut.serial_bit.value = 0


async def send_packet(
    dut,
    packet_type: int,
    plaintext_id: int,
    corrupt_crc: bool,
    plaintext_override: int | None = None,
    idle_after: bool = True,
) -> None:
    plaintext = (
        plaintext_override
        if plaintext_override is not None
        else build_plaintext(plaintext_id)
    )
    ciphertext = aes128_encrypt_block(plaintext)
    crc = calc_crc16(packet_type, ciphertext)

    if corrupt_crc:
        crc ^= 0x0001

    packet = build_packet(packet_type, ciphertext, corrupt_crc=corrupt_crc)

    dut._log.info(
        f"Sending packet: type=0x{packet_type:02x} id=0x{plaintext_id:04x} "
        f"plaintext=0x{plaintext:032x} ciphertext=0x{ciphertext:032x} "
        f"crc=0x{crc:04x} corrupt_crc={int(corrupt_crc)}"
    )

    await send_serial_bits(dut, packet, PACKET_WIDTH - 1, 0, idle_after=idle_after)


async def setup_dut(dut) -> None:
    verify_aes_helper()
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await apply_reset(dut)
    await ReadOnly()

    assert int(dut.classify_valid.value) == 0
    assert int(dut.authorized.value) == 0
    assert int(dut.unauthorized.value) == 0
    assert int(dut.unresponsive.value) == 0


def using_forced_timeout_top(dut) -> bool:
    return dut._name == "rf_secure_id_digital_timeout4"


def random_unauthorized_id(rng: random.Random) -> int:
    while True:
        candidate = rng.randrange(0, 1 << 16)

        if candidate not in AUTHORIZED_IDS:
            return candidate


async def apply_reset(dut) -> None:
    dut.rst_n.value = 0
    dut.serial_bit.value = 0

    await Timer(1, unit="ns")

    for _ in range(3):
        await RisingEdge(dut.clk)

    dut.rst_n.value = 1

    # The active tops use a two-flop reset synchronizer, so wait for internal
    # reset release before starting stimulus.
    for _ in range(3):
        await RisingEdge(dut.clk)


@cocotb.test()
async def authorized_packet_with_correct_crc(dut) -> None:
    if using_forced_timeout_top(dut):
        dut._log.info("Skipping default-path test on short-timeout wrapper.")
        return

    await setup_dut(dut)
    await send_packet(dut, TEST_PACKET_TYPE, AUTHORIZED_ID, corrupt_crc=False)
    await expect_classification(
        dut,
        expected_authorized=1,
        expected_unauthorized=0,
        expected_unresponsive=0,
        expected_latency=CLASSIFY_LATENCY,
    )


@cocotb.test()
async def unauthorized_packet_with_correct_crc(dut) -> None:
    if using_forced_timeout_top(dut):
        dut._log.info("Skipping default-path test on short-timeout wrapper.")
        return

    await setup_dut(dut)
    await send_packet(dut, TEST_PACKET_TYPE, UNAUTHORIZED_ID, corrupt_crc=False)
    await expect_classification(
        dut,
        expected_authorized=0,
        expected_unauthorized=1,
        expected_unresponsive=0,
        expected_latency=CLASSIFY_LATENCY,
    )


@cocotb.test()
async def packet_with_bad_crc(dut) -> None:
    if using_forced_timeout_top(dut):
        dut._log.info("Skipping default-path test on short-timeout wrapper.")
        return

    await setup_dut(dut)
    await send_packet(dut, TEST_PACKET_TYPE, AUTHORIZED_ID, corrupt_crc=True)
    await expect_no_classification(dut)


@cocotb.test()
async def wrong_preamble_produces_no_classification(dut) -> None:
    if using_forced_timeout_top(dut):
        dut._log.info("Skipping default-path test on short-timeout wrapper.")
        return

    await setup_dut(dut)

    monitor = cocotb.start_soon(
        collect_classification_events(dut, PACKET_WIDTH + CLASSIFY_LATENCY + 4)
    )
    wrong_preamble_packet = build_packet(0x00, 0x0, corrupt_crc=False, preamble=0x00)

    await send_serial_bits(dut, wrong_preamble_packet, PACKET_WIDTH - 1, 0)
    events = await monitor

    assert events == [], f"unexpected classification events for wrong preamble: {events}"


@cocotb.test()
async def back_to_back_valid_packets_classify_in_order(dut) -> None:
    if using_forced_timeout_top(dut):
        dut._log.info("Skipping default-path test on short-timeout wrapper.")
        return

    await setup_dut(dut)

    monitor = cocotb.start_soon(collect_classification_events(dut, BACK_TO_BACK_WINDOW))

    await send_packet(
        dut,
        TEST_PACKET_TYPE,
        AUTHORIZED_ID,
        corrupt_crc=False,
        idle_after=False,
    )
    await send_packet(
        dut,
        TEST_PACKET_TYPE,
        UNAUTHORIZED_ID,
        corrupt_crc=False,
    )
    events = await monitor

    assert len(events) == 2, f"expected 2 classification events, saw {events}"
    assert events[0][1:] == (1, 0, 0), f"first classification wrong: {events[0]}"
    assert events[1][1:] == (0, 1, 0), f"second classification wrong: {events[1]}"
    assert events[0][0] < events[1][0], f"classifications out of order: {events}"


@cocotb.test()
async def reset_mid_packet_reception_prevents_classification(dut) -> None:
    if using_forced_timeout_top(dut):
        dut._log.info("Skipping default-path test on short-timeout wrapper.")
        return

    await setup_dut(dut)

    plaintext = build_plaintext(AUTHORIZED_ID)
    ciphertext = aes128_encrypt_block(plaintext)
    packet = build_packet(TEST_PACKET_TYPE, ciphertext, corrupt_crc=False)

    monitor = cocotb.start_soon(
        collect_classification_events(dut, PACKET_WIDTH + CLASSIFY_LATENCY + 8)
    )

    await send_serial_bits(dut, packet, PACKET_WIDTH - 1, 80, idle_after=False)

    await FallingEdge(dut.clk)
    dut.rst_n.value = 0
    dut.serial_bit.value = 0

    for _ in range(2):
        await RisingEdge(dut.clk)

    await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    dut.serial_bit.value = 0

    events = await monitor

    assert events == [], f"unexpected classification after mid-packet reset: {events}"


@cocotb.test()
async def structurally_invalid_plaintext_produces_unresponsive(dut) -> None:
    if using_forced_timeout_top(dut):
        dut._log.info("Skipping default-path test on short-timeout wrapper.")
        return

    await setup_dut(dut)

    invalid_plaintext = build_plaintext(AUTHORIZED_ID, plain_magic=0x0000, reserved=0)
    await send_packet(
        dut,
        TEST_PACKET_TYPE,
        AUTHORIZED_ID,
        corrupt_crc=False,
        plaintext_override=invalid_plaintext,
    )
    await expect_classification(
        dut,
        expected_authorized=0,
        expected_unauthorized=0,
        expected_unresponsive=1,
        expected_latency=DEFAULT_UNRESPONSIVE_LATENCY,
    )


@cocotb.test()
async def forced_timeout_short_threshold_produces_unresponsive(dut) -> None:
    if not using_forced_timeout_top(dut):
        dut._log.info("Skipping short-timeout-only test on default top.")
        return

    await setup_dut(dut)
    await send_packet(dut, TEST_PACKET_TYPE, AUTHORIZED_ID, corrupt_crc=False)
    await expect_classification(
        dut,
        expected_authorized=0,
        expected_unauthorized=0,
        expected_unresponsive=1,
        expected_latency=FORCED_TIMEOUT_LATENCY,
    )


@cocotb.test()
async def randomized_packet_stream_smoke(dut) -> None:
    if using_forced_timeout_top(dut):
        dut._log.info("Skipping default-path test on short-timeout wrapper.")
        return

    await setup_dut(dut)

    rng = random.Random(RANDOM_STRESS_SEED)
    dut._log.info(
        f"Running randomized packet stream smoke test with seed 0x{RANDOM_STRESS_SEED:08x}"
    )

    for packet_idx in range(RANDOM_STRESS_PACKETS):
        scenario = rng.choice(
            (
                "authorized",
                "unauthorized",
                "bad_crc",
                "invalid_plaintext",
                "wrong_preamble",
            )
        )
        dut._log.info(f"Stress packet {packet_idx}: scenario={scenario}")

        if scenario == "authorized":
            plaintext_id = rng.choice(AUTHORIZED_IDS)
            await send_packet(dut, TEST_PACKET_TYPE, plaintext_id, corrupt_crc=False)
            await expect_classification(
                dut,
                expected_authorized=1,
                expected_unauthorized=0,
                expected_unresponsive=0,
                expected_latency=CLASSIFY_LATENCY,
            )
        elif scenario == "unauthorized":
            plaintext_id = random_unauthorized_id(rng)
            await send_packet(dut, TEST_PACKET_TYPE, plaintext_id, corrupt_crc=False)
            await expect_classification(
                dut,
                expected_authorized=0,
                expected_unauthorized=1,
                expected_unresponsive=0,
                expected_latency=CLASSIFY_LATENCY,
            )
        elif scenario == "bad_crc":
            plaintext_id = rng.choice(AUTHORIZED_IDS)
            await send_packet(dut, TEST_PACKET_TYPE, plaintext_id, corrupt_crc=True)
            await expect_no_classification(dut)
        elif scenario == "invalid_plaintext":
            plaintext_id = rng.choice(AUTHORIZED_IDS)

            if rng.randrange(2) == 0:
                wrong_magic = rng.randrange(0, 1 << 16)
                while wrong_magic == PLAIN_MAGIC:
                    wrong_magic = rng.randrange(0, 1 << 16)

                invalid_plaintext = build_plaintext(
                    plaintext_id,
                    plain_magic=wrong_magic,
                    reserved=0,
                )
            else:
                invalid_reserved = rng.randrange(1, 1 << 96)
                invalid_plaintext = build_plaintext(
                    plaintext_id,
                    plain_magic=PLAIN_MAGIC,
                    reserved=invalid_reserved,
                )

            await send_packet(
                dut,
                TEST_PACKET_TYPE,
                plaintext_id,
                corrupt_crc=False,
                plaintext_override=invalid_plaintext,
            )
            await expect_classification(
                dut,
                expected_authorized=0,
                expected_unauthorized=0,
                expected_unresponsive=1,
                expected_latency=DEFAULT_UNRESPONSIVE_LATENCY,
            )
        else:
            wrong_preamble = rng.randrange(0, 1 << 8)
            while wrong_preamble == PREAMBLE:
                wrong_preamble = rng.randrange(0, 1 << 8)

            plaintext_id = rng.choice(AUTHORIZED_IDS)
            plaintext = build_plaintext(plaintext_id)
            ciphertext = aes128_encrypt_block(plaintext)
            wrong_preamble_packet = build_packet(
                TEST_PACKET_TYPE,
                ciphertext,
                corrupt_crc=False,
                preamble=wrong_preamble,
            )

            await send_serial_bits(dut, wrong_preamble_packet, PACKET_WIDTH - 1, 0)
            await expect_no_classification(
                dut,
                observation_cycles=WRONG_PREAMBLE_NO_CLASSIFY_WINDOW,
            )

        for _ in range(4):
            await RisingEdge(dut.clk)


async def expect_classification(
    dut,
    expected_authorized: int,
    expected_unauthorized: int,
    expected_unresponsive: int,
    expected_latency: int,
) -> None:
    saw_classify = False

    for cycle_idx in range(1, expected_latency + 1):
        await RisingEdge(dut.clk)
        await ReadOnly()

        if int(dut.classify_valid.value):
            assert (
                cycle_idx == expected_latency
            ), f"classify_valid arrived at cycle {cycle_idx}, expected {expected_latency}"
            assert int(dut.authorized.value) == expected_authorized
            assert int(dut.unauthorized.value) == expected_unauthorized
            assert int(dut.unresponsive.value) == expected_unresponsive
            assert (
                expected_authorized
                + expected_unauthorized
                + expected_unresponsive
                == 1
            ), "expected outputs must be mutually exclusive"
            saw_classify = True

    assert saw_classify, "classify_valid did not pulse in the expected latency window"

    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.classify_valid.value) == 0


async def collect_classification_events(
    dut, observation_cycles: int
) -> list[tuple[int, int, int, int]]:
    events = []

    for cycle_idx in range(1, observation_cycles + 1):
        await RisingEdge(dut.clk)
        await ReadOnly()

        if int(dut.classify_valid.value):
            outputs = (
                int(dut.authorized.value),
                int(dut.unauthorized.value),
                int(dut.unresponsive.value),
            )
            assert sum(outputs) == 1, f"outputs not mutually exclusive: {outputs}"
            events.append(
                (
                    cycle_idx,
                    outputs[0],
                    outputs[1],
                    outputs[2],
                )
            )

    return events


async def expect_no_classification(
    dut, observation_cycles: int = NO_CLASSIFY_WINDOW
) -> None:
    events = await collect_classification_events(dut, observation_cycles)
    assert events == [], f"unexpected classification events: {events}"
