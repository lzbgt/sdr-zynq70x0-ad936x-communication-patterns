#!/usr/bin/env python3
"""Classify FieldMesh native-IP iperf reports by evidence layer."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def _load_report(path: Path) -> dict[str, Any]:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        raise SystemExit(f"{path}: could not read report: {exc}") from exc
    start = text.find("{")
    if start < 0:
        raise SystemExit(f"{path}: report does not contain JSON")
    try:
        report = json.loads(text[start:])
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(report, dict):
        raise SystemExit(f"{path}: report must be a JSON object")
    return report


def _is_true(value: Any) -> bool:
    return value is True or value == 1 or value == "1" or value == "true"


def _positive_number(report: dict[str, Any], key: str) -> bool:
    value = report.get(key)
    return isinstance(value, (int, float)) and value > 0


def _non_negative_number(report: dict[str, Any], key: str) -> bool:
    value = report.get(key)
    return isinstance(value, (int, float)) and value >= 0


def _percent(report: dict[str, Any], key: str) -> bool:
    value = report.get(key)
    return isinstance(value, (int, float)) and 0 <= value <= 100


def _require_iperf_quality(
    report: dict[str, Any],
    label: str,
    *,
    tcp_prefix: str = "",
    udp_prefix: str = "",
) -> list[str]:
    errors: list[str] = []
    required_positive = (
        f"{tcp_prefix}tcp_duration_s",
        f"{udp_prefix}udp_duration_s",
        f"{udp_prefix}udp_packets",
    )
    for key in required_positive:
        if not _positive_number(report, key):
            errors.append(f"{label}: {key} must be > 0")
    for key in (f"{udp_prefix}udp_jitter_ms", f"{udp_prefix}udp_lost_packets"):
        if not _non_negative_number(report, key):
            errors.append(f"{label}: {key} must be >= 0")
    if not _percent(report, f"{udp_prefix}udp_lost_percent"):
        errors.append(f"{label}: {udp_prefix}udp_lost_percent must be 0..100")
    return errors


def _validate_iio_ack_pipeline(report: dict[str, Any], label: str) -> list[str]:
    errors: list[str] = []
    depth = report.get("iio_bridge_source_ack_pipeline_depth")
    if not isinstance(depth, int):
        depth = 0
    batch_size = report.get("iio_bridge_rf_burst_batch_size")
    if not isinstance(batch_size, int):
        batch_size = 0
    fair_enabled = report.get("iio_bridge_direction_fair_service_enabled") is True
    if (
        depth <= 1
        and batch_size <= 1
        and not fair_enabled
        and not _is_true(report.get("iio_rf_bridge"))
    ):
        return errors
    if not _is_true(report.get("iio_rf_bridge")):
        errors.append(f"{label}: IIO pipeline evidence requires iio_rf_bridge=true")
        return errors
    if report.get("iio_bridge_rf_service_policy_proven") is not True:
        errors.append(f"{label}: IIO RF service policy C proof is missing")
    if report.get("iio_bridge_rf_service_policy_native_c") is not True:
        errors.append(f"{label}: IIO RF service policy must be native C")
    if report.get("iio_bridge_rf_service_policy_production_iio") is not True:
        errors.append(f"{label}: IIO RF service policy must accept production IIO")
    if report.get("iio_bridge_rf_service_policy_lease_batch_frames") != 4:
        errors.append(f"{label}: IIO RF service policy lease batch must be 4")
    if report.get("iio_bridge_rf_service_policy_max_frames_per_rf_burst") != 2:
        errors.append(f"{label}: IIO RF service policy sub-burst cap must be 2")
    if report.get("iio_bridge_rf_service_policy_requires_reverse_service") is not True:
        errors.append(f"{label}: IIO RF service policy must require reverse service")
    if (
        report.get("iio_bridge_rf_service_policy_lease_priority")
        != "tcp-control-flow-udp-after-control"
    ):
        errors.append(f"{label}: IIO RF service policy must use hybrid lease priority")
    if report.get("iio_bridge_rf_service_policy_in_burst_priority_preemption") is not True:
        errors.append(f"{label}: IIO RF service policy must enable in-burst priority preemption")
    if report.get("iio_bridge_adaptive_modem_profile_policy_proven") is not True:
        errors.append(f"{label}: adaptive modem profile policy proof is missing")
    if report.get("iio_bridge_adaptive_modem_profile_policy_native_c") is not True:
        errors.append(f"{label}: adaptive modem profile policy must be native C")
    if report.get("iio_bridge_fast_primary_min_raw_bitrate_bps") != 20_000:
        errors.append(f"{label}: fast-primary PHY floor must be 20 kbps")
    if report.get("iio_bridge_fast_primary_requires_primary_decode") is not True:
        errors.append(f"{label}: fast-primary profile must require primary decode")
    if report.get("iio_bridge_fast_primary_rejects_modem_retry") is not True:
        errors.append(f"{label}: fast-primary profile must reject modem retry fallback")
    if report.get("iio_bridge_fast_primary_decision") != "fast_primary":
        errors.append(f"{label}: C modem profile policy did not select fast_primary")
    if report.get("iio_bridge_retry_fallback_decision") != "retry_fallback":
        errors.append(f"{label}: C modem profile policy did not classify retry fallback")
    if report.get("iio_bridge_fast_primary_high_rate_proven") is not True:
        errors.append(f"{label}: C modem profile policy did not prove fast primary high-rate")
    if report.get("iio_bridge_retry_fallback_high_rate_proven") is not False:
        errors.append(f"{label}: C modem profile policy treated retry fallback as high-rate")
    if report.get("iio_bridge_adaptive_modem_profile_measured_quality_policy") is not True:
        errors.append(f"{label}: adaptive modem profile measured-quality policy is missing")
    if report.get("iio_bridge_adaptive_modem_profile_measured_quality_native_c") is not True:
        errors.append(f"{label}: adaptive modem measured-quality policy must be native C")
    if report.get("iio_bridge_fast_primary_min_decode_attempts") != 4:
        errors.append(f"{label}: fast-primary quality gate must require four decode attempts")
    if report.get("iio_bridge_fast_primary_max_primary_per_mille") != 0:
        errors.append(f"{label}: fast-primary quality gate must require zero primary PER")
    if report.get("iio_bridge_fast_primary_quality_per_mille") != 0:
        errors.append(f"{label}: fast-primary quality fixture must prove zero PER")
    retry_quality_per_mille = report.get("iio_bridge_retry_fallback_quality_per_mille")
    if not isinstance(retry_quality_per_mille, int) or retry_quality_per_mille <= 0:
        errors.append(f"{label}: retry fallback quality fixture must show measured PER")
    if report.get("iio_bridge_fast_primary_quality_decision") != "fast_primary":
        errors.append(f"{label}: measured quality policy did not select fast_primary")
    if report.get("iio_bridge_retry_fallback_quality_decision") != "retry_fallback":
        errors.append(f"{label}: measured quality policy did not select retry_fallback")
    if report.get("iio_bridge_insufficient_quality_decision") != "hold":
        errors.append(f"{label}: insufficient measured quality must hold current profile")
    if report.get("iio_bridge_phy_adaptive_mcs_decision") != "fast_primary":
        errors.append(f"{label}: live adaptive MCS decision must select fast_primary")
    mcs_decisions = report.get("iio_bridge_phy_adaptive_mcs_decision_by_direction")
    if not isinstance(mcs_decisions, dict) or not mcs_decisions:
        errors.append(f"{label}: live adaptive MCS direction decisions are missing")
    elif any(decision != "fast_primary" for decision in mcs_decisions.values()):
        errors.append(f"{label}: live adaptive MCS direction decisions must be fast_primary")
    if report.get("iio_bridge_phy_adaptive_mcs_live_quality_bound") is not True:
        errors.append(f"{label}: live adaptive MCS decision is not bound to measured quality")
    mcs_quality_bound = report.get("iio_bridge_phy_adaptive_mcs_live_quality_bound_by_direction")
    if not isinstance(mcs_quality_bound, dict) or not mcs_quality_bound:
        errors.append(f"{label}: live adaptive MCS quality-bound direction proof is missing")
    elif any(value is not True for value in mcs_quality_bound.values()):
        errors.append(f"{label}: every live adaptive MCS direction must be quality-bound")
    if (
        report.get("iio_bridge_phy_adaptive_mcs_quality_source")
        != "state_daemon_rf_modem_quality_accumulator"
    ):
        errors.append(f"{label}: live adaptive MCS quality must be accumulated in the state daemon")
    mcs_quality_sources = report.get("iio_bridge_phy_adaptive_mcs_quality_source_by_direction")
    if not isinstance(mcs_quality_sources, dict) or not mcs_quality_sources:
        errors.append(f"{label}: live adaptive MCS quality source proof is missing")
    elif any(
        source != "state_daemon_rf_modem_quality_accumulator"
        for source in mcs_quality_sources.values()
    ):
        errors.append(f"{label}: every live adaptive MCS direction must use the state-daemon quality accumulator")
    if not isinstance(report.get("iio_bridge_phy_adaptive_mcs_quality_updates"), int) or (
        report.get("iio_bridge_phy_adaptive_mcs_quality_updates") < 1
    ):
        errors.append(f"{label}: state-daemon adaptive MCS quality accumulator was not updated")
    if report.get("iio_bridge_phy_adaptive_mcs_quality_update_failures") != 0:
        errors.append(f"{label}: state-daemon adaptive MCS quality accumulator reported failures")
    if not isinstance(report.get("iio_bridge_phy_adaptive_mcs_decision_polls"), int) or (
        report.get("iio_bridge_phy_adaptive_mcs_decision_polls") < 1
    ):
        errors.append(f"{label}: live adaptive MCS decision was not exercised")
    if report.get("iio_bridge_phy_adaptive_mcs_decision_failures") != 0:
        errors.append(f"{label}: live adaptive MCS decision reported failures")
    if report.get("iio_bridge_phy_adaptive_mcs_pre_burst_selection") != "fast_primary":
        errors.append(f"{label}: pre-burst adaptive MCS selection must select fast_primary")
    pre_burst_selections = report.get(
        "iio_bridge_phy_adaptive_mcs_pre_burst_selection_by_direction"
    )
    if not isinstance(pre_burst_selections, dict) or not pre_burst_selections:
        errors.append(f"{label}: pre-burst adaptive MCS direction selections are missing")
    elif any(selection != "fast_primary" for selection in pre_burst_selections.values()):
        errors.append(f"{label}: pre-burst adaptive MCS direction selections must be fast_primary")
    if (
        report.get("iio_bridge_phy_adaptive_mcs_pre_burst_profile_source")
        != "state_daemon_rf_service_loop_tick"
    ):
        errors.append(f"{label}: pre-burst adaptive MCS selection must be state-daemon owned")
    pre_burst_sources = report.get(
        "iio_bridge_phy_adaptive_mcs_pre_burst_profile_source_by_direction"
    )
    if not isinstance(pre_burst_sources, dict) or not pre_burst_sources:
        errors.append(f"{label}: pre-burst adaptive MCS source proof is missing")
    elif any(
        source != "state_daemon_rf_service_loop_tick"
        for source in pre_burst_sources.values()
    ):
        errors.append(f"{label}: every pre-burst adaptive MCS direction must be state-daemon owned")
    if (
        report.get("iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source")
        != "state_daemon_rf_service_loop_tick"
    ):
        errors.append(f"{label}: pre-burst modem profile application must be state-daemon owned")
    application_sources = report.get(
        "iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source_by_direction"
    )
    if not isinstance(application_sources, dict) or not application_sources:
        errors.append(f"{label}: pre-burst modem profile application source proof is missing")
    elif any(
        source != "state_daemon_rf_service_loop_tick"
        for source in application_sources.values()
    ):
        errors.append(f"{label}: every modem profile application must be state-daemon owned")
    if report.get("iio_bridge_phy_native_modem_profile_application") is not True:
        errors.append(f"{label}: native modem profile application was not proven")
    native_profile_by_direction = report.get(
        "iio_bridge_phy_native_modem_profile_application_by_direction"
    )
    if not isinstance(native_profile_by_direction, dict) or not native_profile_by_direction:
        errors.append(f"{label}: native modem profile application direction proof is missing")
    elif any(value is not True for value in native_profile_by_direction.values()):
        errors.append(f"{label}: every direction must prove native modem profile application")
    if report.get("iio_bridge_phy_python_modem_profile_mapping") is not False:
        errors.append(f"{label}: Python modem profile mapping must be disabled")
    if report.get("iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound") is not True:
        errors.append(f"{label}: pre-burst adaptive MCS selection is not bound to measured quality")
    pre_burst_quality_bound = report.get(
        "iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound_by_direction"
    )
    if not isinstance(pre_burst_quality_bound, dict) or not pre_burst_quality_bound:
        errors.append(f"{label}: pre-burst adaptive MCS quality-bound proof is missing")
    elif any(value is not True for value in pre_burst_quality_bound.values()):
        errors.append(f"{label}: every pre-burst adaptive MCS direction must be quality-bound")
    if not isinstance(
        report.get("iio_bridge_phy_adaptive_mcs_pre_burst_selection_polls"), int
    ) or report.get("iio_bridge_phy_adaptive_mcs_pre_burst_selection_polls") < 1:
        errors.append(f"{label}: pre-burst adaptive MCS selection was not exercised")
    if report.get("iio_bridge_phy_adaptive_mcs_pre_burst_selection_failures") != 0:
        errors.append(f"{label}: pre-burst adaptive MCS selection reported failures")
    if report.get("iio_bridge_native_rf_service_worker_required") is not True:
        errors.append(f"{label}: native RF service worker proof must be required")
    if report.get("iio_bridge_native_rf_service_worker_proven") is not True:
        errors.append(f"{label}: native RF service worker proof is missing")
    if report.get("iio_bridge_native_service_burst_leases_enabled") is not True:
        errors.append(f"{label}: native RF service burst leases must be enabled")
    if not isinstance(report.get("iio_bridge_native_service_burst_leases"), int) or (
        report.get("iio_bridge_native_service_burst_leases") < 1
    ):
        errors.append(f"{label}: native RF service burst lease proof is missing")
    if report.get("iio_bridge_native_service_loop_tick_enabled") is not True:
        errors.append(f"{label}: native RF service loop tick must be enabled")
    if report.get("iio_bridge_native_service_loop_tick_proven") is not True:
        errors.append(f"{label}: native RF service loop tick proof is missing")
    if not isinstance(report.get("iio_bridge_native_service_loop_ticks"), int) or (
        report.get("iio_bridge_native_service_loop_ticks") < 1
    ):
        errors.append(f"{label}: native RF service loop tick was not exercised")
    if report.get("iio_bridge_native_cross_daemon_transport_loop_required") is not True:
        errors.append(f"{label}: native cross-daemon RF transport loop must be required")
    if report.get("iio_bridge_native_cross_daemon_transport_loop_proven") is not True:
        errors.append(f"{label}: native cross-daemon RF transport loop proof is missing")
    if not isinstance(
        report.get("iio_bridge_native_cross_daemon_transport_loop_ticks"), int
    ) or report.get("iio_bridge_native_cross_daemon_transport_loop_ticks") < 1:
        errors.append(f"{label}: native cross-daemon RF transport loop was not exercised")
    if int(report.get("iio_bridge_native_cross_daemon_transport_loop_failures") or 0) != 0:
        errors.append(f"{label}: native cross-daemon RF transport loop reported failures")
    loop_tick_status = report.get("iio_bridge_native_service_loop_tick_status")
    if not isinstance(loop_tick_status, dict) or not loop_tick_status:
        errors.append(f"{label}: native RF service loop tick status is missing")
    elif not all(
        isinstance(status, dict)
        and status.get("native_service_loop_tick") == 1
        and status.get("native_service_loop_worker") == 1
        and status.get("persistent_native_bidirectional_rf_service_loop") == 1
        and status.get("native_cross_daemon_transport_loop") == 1
        and status.get("native_peer_scheduler_query") == 1
        and status.get("persistent_native_transport_loop_process") == 1
        and status.get("native_bidirectional_direction_decision") == 1
        and status.get("native_service_burst") == 1
        and status.get("service_policy_bound") == 1
        and status.get("production_iio_policy") == 1
        and status.get("next_boundary") == "native_cross_daemon_transport_worker_process"
        and isinstance(status.get("frames"), int)
        and isinstance(status.get("service_order_rank"), int)
        and status.get("in_burst_priority_preemption") == 1
        and isinstance(status.get("in_burst_priority_preempted"), int)
        and isinstance(status.get("in_burst_priority_preemption_count"), int)
        and isinstance(status.get("in_burst_priority_multiplexing"), int)
        for status in loop_tick_status.values()
    ):
        errors.append(f"{label}: native RF service loop tick status is incomplete")
    if report.get("iio_bridge_native_service_loop_worker_required") is not True:
        errors.append(f"{label}: native RF service loop worker proof must be required")
    if report.get("iio_bridge_native_service_loop_worker_proven") is not True:
        errors.append(f"{label}: native RF service loop worker proof is missing")
    if not isinstance(report.get("iio_bridge_native_service_loop_worker_starts"), int) or (
        report.get("iio_bridge_native_service_loop_worker_starts") < 2
    ):
        errors.append(f"{label}: native RF service loop worker start proof is missing")
    if not isinstance(
        report.get("iio_bridge_native_service_loop_worker_status_polls"), int
    ) or report.get("iio_bridge_native_service_loop_worker_status_polls") < 2:
        errors.append(f"{label}: native RF service loop worker status proof is missing")
    worker_status = report.get("iio_bridge_native_service_loop_worker_status")
    if not isinstance(worker_status, dict) or sorted(worker_status) != ["z103", "z203"]:
        errors.append(f"{label}: native RF service loop worker status must include z203 and z103")
    elif not all(
        isinstance(status, dict)
        and status.get("native_service_loop_worker") == 1
        and status.get("persistent_native_bidirectional_rf_service_loop") == 1
        and status.get("native_service_loop_tick") == 1
        and status.get("native_bidirectional_direction_decision") == 1
        and status.get("native_service_burst") == 1
        and status.get("service_policy_bound") == 1
        and status.get("production_iio_policy") == 1
        and status.get("running") == 1
        and isinstance(status.get("ticks"), int)
        and status.get("ticks") >= 1
        and isinstance(status.get("bursts"), int)
        and status.get("bursts") >= 1
        for status in worker_status.values()
    ):
        errors.append(f"{label}: native RF service loop worker status is incomplete")
    if report.get("iio_bridge_in_burst_priority_preemption_enabled") is not True:
        errors.append(f"{label}: IIO bridge in-burst priority preemption must be enabled")
    if report.get("iio_bridge_in_burst_priority_preemption_exercised") is not True:
        errors.append(f"{label}: IIO bridge in-burst priority preemption was not exercised")
    if not isinstance(report.get("iio_bridge_in_burst_priority_preemptions"), int) or (
        report.get("iio_bridge_in_burst_priority_preemptions") < 1
    ):
        errors.append(f"{label}: IIO bridge in-burst priority preemption count is missing")
    if report.get("iio_bridge_in_burst_priority_multiplexing_exercised") is not True:
        errors.append(f"{label}: IIO bridge in-burst priority multiplexing was not exercised")
    if not isinstance(
        report.get("iio_bridge_in_burst_priority_multiplexing_events"), int
    ) or report.get("iio_bridge_in_burst_priority_multiplexing_events") < 1:
        errors.append(f"{label}: IIO bridge in-burst priority multiplexing count is missing")
    if report.get("iio_bridge_native_direction_scheduler_enabled") is not True:
        errors.append(f"{label}: native RF direction scheduler must be enabled")
    if report.get("iio_bridge_native_direction_scheduler_proven") is not True:
        errors.append(f"{label}: native RF direction scheduler proof is missing")
    if not isinstance(
        report.get("iio_bridge_native_direction_scheduler_status_polls"), int
    ) or report.get("iio_bridge_native_direction_scheduler_status_polls") < 1:
        errors.append(f"{label}: native RF direction scheduler was not exercised")
    scheduler_status = report.get("iio_bridge_native_direction_scheduler_status")
    if not isinstance(scheduler_status, dict) or not scheduler_status:
        errors.append(f"{label}: native RF direction scheduler status is missing")
    elif not all(
        isinstance(status, dict)
        and status.get("native_direction_scheduler") == 1
        and status.get("scheduler_score_native_c") == 1
        and status.get("service_policy_bound") == 1
        and isinstance(status.get("scheduler_score"), int)
        for status in scheduler_status.values()
    ):
        errors.append(f"{label}: native RF direction scheduler status is incomplete")
    if report.get("iio_bridge_native_bidirectional_direction_decision_enabled") is not True:
        errors.append(f"{label}: native RF bidirectional decision must be enabled")
    if report.get("iio_bridge_native_bidirectional_direction_decision_proven") is not True:
        errors.append(f"{label}: native RF bidirectional decision proof is missing")
    if not isinstance(
        report.get("iio_bridge_native_bidirectional_direction_decision_polls"), int
    ) or report.get("iio_bridge_native_bidirectional_direction_decision_polls") < 1:
        errors.append(f"{label}: native RF bidirectional decision was not exercised")
    decision_status = report.get("iio_bridge_native_bidirectional_direction_decision_status")
    if not isinstance(decision_status, dict) or not decision_status:
        errors.append(f"{label}: native RF bidirectional decision status is missing")
    elif not all(
        isinstance(status, dict)
        and status.get("native_bidirectional_direction_decision") == 1
        and status.get("native_direction_scheduler") == 1
        and status.get("scheduler_score_native_c") == 1
        and status.get("service_policy_bound") == 1
        and isinstance(status.get("local_scheduler_score"), int)
        and isinstance(status.get("peer_scheduler_score"), int)
        and isinstance(status.get("service_local_first"), int)
        and isinstance(status.get("yield_to_peer"), int)
        and isinstance(status.get("service_order_rank"), int)
        for status in decision_status.values()
    ):
        errors.append(f"{label}: native RF bidirectional decision status is incomplete")
    worker_status = report.get("iio_bridge_native_rf_service_worker_status")
    if not isinstance(worker_status, dict) or sorted(worker_status) != ["z103", "z203"]:
        errors.append(f"{label}: native RF service worker status must include z203 and z103")
    else:
        for endpoint, status in sorted(worker_status.items()):
            if not isinstance(status, dict):
                errors.append(f"{label}: {endpoint} native RF worker status is not an object")
                continue
            for key in (
                "native_rf_service_worker",
                "native_rf_service_control_plane",
                "service_policy_bound",
                "production_iio_policy",
            ):
                if status.get(key) != 1:
                    errors.append(f"{label}: {endpoint} native RF worker {key} is not proven")
    if report.get("iio_bridge_lease_priority") != "tcp-control-flow-udp-after-control":
        errors.append(
            f"{label}: IIO bridge lease priority must be tcp-control-flow-udp-after-control"
        )
    if report.get("iio_bridge_persistent_burst_helper") is not True:
        errors.append(f"{label}: IIO bridge must use persistent burst helper")
    if report.get("iio_bridge_native_iio_burst_worker_required") is not True:
        errors.append(f"{label}: native IIO burst worker proof must be required")
    if report.get("iio_bridge_native_iio_burst_worker_proven") is not True:
        errors.append(f"{label}: native IIO burst worker proof is missing")
    invocations = report.get("iio_bridge_native_iio_burst_worker_invocations")
    if not isinstance(invocations, int) or invocations < 1:
        errors.append(f"{label}: native IIO burst worker was not exercised")
    if int(report.get("iio_bridge_native_iio_burst_worker_failures") or 0) != 0:
        errors.append(f"{label}: native IIO burst worker reported failures")
    if report.get("iio_bridge_native_iio_burst_worker_lifecycle_proven") is not True:
        errors.append(f"{label}: native IIO burst worker lifecycle proof is missing")
    lifecycle_invocations = report.get(
        "iio_bridge_native_iio_burst_worker_lifecycle_invocations"
    )
    if not isinstance(lifecycle_invocations, int) or lifecycle_invocations < 1:
        errors.append(f"{label}: native IIO burst worker lifecycle was not exercised")
    if (
        int(report.get("iio_bridge_native_iio_burst_worker_lifecycle_failures") or 0)
        != 0
    ):
        errors.append(f"{label}: native IIO burst worker lifecycle reported failures")
    if report.get("iio_bridge_native_iio_burst_transport_worker_proven") is not True:
        errors.append(f"{label}: native IIO burst transport worker proof is missing")
    transport_invocations = report.get(
        "iio_bridge_native_iio_burst_transport_worker_invocations"
    )
    if not isinstance(transport_invocations, int) or transport_invocations < 1:
        errors.append(f"{label}: native IIO burst transport worker was not exercised")
    if (
        int(report.get("iio_bridge_native_iio_burst_transport_worker_failures") or 0)
        != 0
    ):
        errors.append(f"{label}: native IIO burst transport worker reported failures")
    if report.get("iio_bridge_native_iio_burst_transport_session_proven") is not True:
        errors.append(f"{label}: native IIO burst transport session proof is missing")
    session_invocations = report.get(
        "iio_bridge_native_iio_burst_transport_session_invocations"
    )
    if not isinstance(session_invocations, int) or session_invocations < 1:
        errors.append(f"{label}: native IIO burst transport session was not exercised")
    if (
        int(report.get("iio_bridge_native_iio_burst_transport_session_failures") or 0)
        != 0
    ):
        errors.append(f"{label}: native IIO burst transport session reported failures")
    if report.get("iio_bridge_native_iio_burst_transport_service_loop_proven") is not True:
        errors.append(f"{label}: native IIO burst transport service loop proof is missing")
    service_loop_invocations = report.get(
        "iio_bridge_native_iio_burst_transport_service_loop_invocations"
    )
    if not isinstance(service_loop_invocations, int) or service_loop_invocations < 1:
        errors.append(f"{label}: native IIO burst transport service loop was not exercised")
    if (
        int(report.get("iio_bridge_native_iio_burst_transport_service_loop_failures") or 0)
        != 0
    ):
        errors.append(f"{label}: native IIO burst transport service loop reported failures")
    if report.get("iio_bridge_native_iio_burst_transport_scheduler_proven") is not True:
        errors.append(f"{label}: native IIO burst transport scheduler proof is missing")
    scheduler_invocations = report.get(
        "iio_bridge_native_iio_burst_transport_scheduler_invocations"
    )
    if not isinstance(scheduler_invocations, int) or scheduler_invocations < 1:
        errors.append(f"{label}: native IIO burst transport scheduler was not exercised")
    if (
        int(report.get("iio_bridge_native_iio_burst_transport_scheduler_failures") or 0)
        != 0
    ):
        errors.append(f"{label}: native IIO burst transport scheduler reported failures")
    if (
        report.get("iio_bridge_native_iio_burst_transport_autonomous_loop_proven")
        is not True
    ):
        errors.append(f"{label}: native IIO burst autonomous transport loop proof is missing")
    autonomous_invocations = report.get(
        "iio_bridge_native_iio_burst_transport_autonomous_loop_invocations"
    )
    if not isinstance(autonomous_invocations, int) or autonomous_invocations < 1:
        errors.append(f"{label}: native IIO burst autonomous transport loop was not exercised")
    if (
        int(
            report.get("iio_bridge_native_iio_burst_transport_autonomous_loop_failures")
            or 0
        )
        != 0
    ):
        errors.append(f"{label}: native IIO burst autonomous transport loop reported failures")
    if (
        report.get("iio_bridge_native_iio_burst_transport_background_daemon_proven")
        is not True
    ):
        errors.append(f"{label}: native IIO burst background transport daemon proof is missing")
    background_invocations = report.get(
        "iio_bridge_native_iio_burst_transport_background_daemon_invocations"
    )
    if not isinstance(background_invocations, int) or background_invocations < 1:
        errors.append(f"{label}: native IIO burst background transport daemon was not exercised")
    if (
        int(
            report.get("iio_bridge_native_iio_burst_transport_background_daemon_failures")
            or 0
        )
        != 0
    ):
        errors.append(f"{label}: native IIO burst background transport daemon reported failures")
    if (
        report.get("iio_bridge_native_iio_burst_integrated_rf_service_daemon_proven")
        is not True
    ):
        errors.append(f"{label}: native IIO burst integrated RF service daemon proof is missing")
    integrated_invocations = report.get(
        "iio_bridge_native_iio_burst_integrated_rf_service_daemon_invocations"
    )
    if not isinstance(integrated_invocations, int) or integrated_invocations < 1:
        errors.append(f"{label}: native IIO burst integrated RF service daemon was not exercised")
    if (
        int(
            report.get("iio_bridge_native_iio_burst_integrated_rf_service_daemon_failures")
            or 0
        )
        != 0
    ):
        errors.append(f"{label}: native IIO burst integrated RF service daemon reported failures")
    if (
        report.get("iio_bridge_native_iio_burst_state_daemon_transport_queue_proven")
        is not True
    ):
        errors.append(f"{label}: native state-daemon transport queue proof is missing")
    queue_invocations = report.get(
        "iio_bridge_native_iio_burst_state_daemon_transport_queue_invocations"
    )
    if not isinstance(queue_invocations, int) or queue_invocations < 1:
        errors.append(f"{label}: native state-daemon transport queue was not exercised")
    if (
        int(
            report.get("iio_bridge_native_iio_burst_state_daemon_transport_queue_failures")
            or 0
        )
        != 0
    ):
        errors.append(f"{label}: native state-daemon transport queue reported failures")
    if (
        report.get("iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_proven")
        is not True
    ):
        errors.append(f"{label}: native state-daemon transport lifecycle proof is missing")
    lifecycle_invocations = report.get(
        "iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_invocations"
    )
    if not isinstance(lifecycle_invocations, int) or lifecycle_invocations < 1:
        errors.append(f"{label}: native state-daemon transport lifecycle was not exercised")
    if (
        int(
            report.get(
                "iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_failures"
            )
            or 0
        )
        != 0
    ):
        errors.append(f"{label}: native state-daemon transport lifecycle reported failures")
    if (
        report.get("iio_bridge_native_iio_burst_state_daemon_modem_profile_proven")
        is not True
    ):
        errors.append(f"{label}: native state-daemon modem profile helper proof is missing")
    modem_profile_invocations = report.get(
        "iio_bridge_native_iio_burst_state_daemon_modem_profile_invocations"
    )
    if not isinstance(modem_profile_invocations, int) or modem_profile_invocations < 1:
        errors.append(f"{label}: native state-daemon modem profile helper was not exercised")
    if (
        int(
            report.get(
                "iio_bridge_native_iio_burst_state_daemon_modem_profile_failures"
            )
            or 0
        )
        != 0
    ):
        errors.append(f"{label}: native state-daemon modem profile helper reported failures")
    if report.get("iio_bridge_state_daemon_iio_transport_required") is not True:
        errors.append(f"{label}: state-daemon IIO transport proof must be required")
    if report.get("iio_bridge_state_daemon_iio_transport_proven") is not True:
        errors.append(f"{label}: state-daemon IIO transport proof is missing")
    transport_status_polls = report.get("iio_bridge_state_daemon_iio_transport_status_polls")
    if not isinstance(transport_status_polls, int) or transport_status_polls < 2:
        errors.append(
            f"{label}: state-daemon IIO transport status must be proven on both endpoints"
        )
    if int(report.get("iio_bridge_state_daemon_iio_transport_status_failures") or 0) != 0:
        errors.append(f"{label}: state-daemon IIO transport status reported failures")
    if report.get("iio_bridge_state_daemon_iio_transport_enqueue_proven") is not True:
        errors.append(f"{label}: state-daemon IIO transport enqueue/drain proof is missing")
    state_starts = report.get("iio_bridge_state_daemon_iio_transport_starts")
    if not isinstance(state_starts, int) or state_starts < 2:
        errors.append(f"{label}: state-daemon IIO transport start proof must cover both endpoints")
    state_enqueues = report.get("iio_bridge_state_daemon_iio_transport_enqueues")
    state_drains = report.get("iio_bridge_state_daemon_iio_transport_drains")
    state_exec_runs = report.get(
        "iio_bridge_state_daemon_iio_transport_execution_worker_runs"
    )
    if not isinstance(state_enqueues, int) or state_enqueues < 1:
        errors.append(f"{label}: state-daemon IIO transport enqueue count is missing")
    if not isinstance(state_drains, int) or state_drains < state_enqueues:
        errors.append(f"{label}: state-daemon IIO transport drain count is below enqueue count")
    if not isinstance(state_exec_runs, int) or state_exec_runs < state_enqueues:
        errors.append(
            f"{label}: state-daemon IIO transport execution worker did not cover enqueues"
        )
    if int(report.get("iio_bridge_state_daemon_iio_transport_enqueue_failures") or 0) != 0:
        errors.append(f"{label}: state-daemon IIO transport enqueue reported failures")
    sample_rate_hz = report.get("iio_bridge_sample_rate_hz")
    rf_bandwidth_hz = report.get("iio_bridge_rf_bandwidth_hz")
    if not isinstance(sample_rate_hz, int) or sample_rate_hz <= 0:
        errors.append(f"{label}: IIO bridge sample-rate evidence is missing")
    if not isinstance(rf_bandwidth_hz, int) or rf_bandwidth_hz < 1_000_000:
        errors.append(f"{label}: IIO bridge RF bandwidth must be at least 1 MHz")
    phy_raw = report.get("iio_bridge_phy_raw_bitrate_bps")
    if not isinstance(phy_raw, dict) or sorted(phy_raw) != ["z103_to_z203", "z203_to_z103"]:
        errors.append(f"{label}: IIO bridge PHY raw bitrate evidence must include both directions")
    else:
        for direction, value in sorted(phy_raw.items()):
            if not isinstance(value, (int, float)) or value <= 0:
                errors.append(
                    f"{label}: IIO bridge PHY raw bitrate for {direction} must be > 0"
                )
    min_phy_raw = report.get("iio_bridge_phy_min_raw_bitrate_bps")
    if not isinstance(min_phy_raw, (int, float)) or min_phy_raw <= 0:
        errors.append(f"{label}: IIO bridge minimum PHY raw bitrate evidence is missing")
    elif float(min_phy_raw) < 20_000.0:
        errors.append(
            f"{label}: IIO bridge minimum PHY raw bitrate must be at least 20 kbps"
        )
    primary_phy_raw = report.get("iio_bridge_phy_primary_raw_bitrate_bps")
    if not isinstance(primary_phy_raw, dict) or sorted(primary_phy_raw) != [
        "z103_to_z203",
        "z203_to_z103",
    ]:
        errors.append(f"{label}: IIO bridge primary PHY raw bitrate evidence is missing")
    else:
        for direction, value in sorted(primary_phy_raw.items()):
            if not isinstance(value, (int, float)) or value <= 0:
                errors.append(
                    f"{label}: IIO bridge primary PHY raw bitrate for {direction} must be > 0"
                )
    min_primary_phy_raw = report.get("iio_bridge_phy_min_primary_raw_bitrate_bps")
    if not isinstance(min_primary_phy_raw, (int, float)) or min_primary_phy_raw <= 0:
        errors.append(f"{label}: IIO bridge minimum primary PHY raw bitrate is missing")
    elif float(min_primary_phy_raw) < 20_000.0:
        errors.append(
            f"{label}: IIO bridge minimum primary PHY raw bitrate must be at least 20 kbps"
        )
    effective_phy_raw = report.get("iio_bridge_phy_effective_raw_bitrate_bps")
    if not isinstance(effective_phy_raw, dict) or sorted(effective_phy_raw) != [
        "z103_to_z203",
        "z203_to_z103",
    ]:
        errors.append(f"{label}: IIO bridge effective PHY raw bitrate evidence is missing")
    else:
        for direction, value in sorted(effective_phy_raw.items()):
            if not isinstance(value, (int, float)) or value <= 0:
                errors.append(
                    f"{label}: IIO bridge effective PHY raw bitrate for {direction} must be > 0"
                )
    min_effective_phy_raw = report.get("iio_bridge_phy_min_effective_raw_bitrate_bps")
    if not isinstance(min_effective_phy_raw, (int, float)) or min_effective_phy_raw <= 0:
        errors.append(f"{label}: IIO bridge minimum effective PHY raw bitrate is missing")
    elif float(min_effective_phy_raw) < 20_000.0:
        errors.append(
            f"{label}: IIO bridge minimum effective PHY raw bitrate must be at least 20 kbps"
        )
    fast_primary_by_direction = report.get(
        "iio_bridge_phy_fast_primary_decode_proven_by_direction"
    )
    if not isinstance(fast_primary_by_direction, dict) or sorted(
        fast_primary_by_direction
    ) != ["z103_to_z203", "z203_to_z103"]:
        errors.append(f"{label}: fast primary PHY decode proof by direction is missing")
    elif not all(value is True for value in fast_primary_by_direction.values()):
        errors.append(f"{label}: fast primary PHY decode must be proven in both directions")
    if report.get("iio_bridge_phy_fast_primary_decode_proven") is not True:
        errors.append(f"{label}: fast primary PHY decode proof is missing")
    retry_used_by_direction = report.get("iio_bridge_phy_modem_retry_used_by_direction")
    if not isinstance(retry_used_by_direction, dict) or sorted(retry_used_by_direction) != [
        "z103_to_z203",
        "z203_to_z103",
    ]:
        errors.append(f"{label}: modem retry-use evidence by direction is missing")
    elif any(value is True for value in retry_used_by_direction.values()):
        errors.append(f"{label}: high-rate PHY evidence must not rely on modem retry fallback")
    if report.get("iio_bridge_phy_modem_retry_used") is True:
        errors.append(f"{label}: high-rate PHY evidence used modem retry fallback")
    transport_status = report.get("iio_bridge_state_daemon_iio_transport_status")
    if not isinstance(transport_status, dict) or sorted(transport_status) != ["z103", "z203"]:
        errors.append(f"{label}: state-daemon IIO transport status must include z203 and z103")
    else:
        for endpoint, status in sorted(transport_status.items()):
            if not isinstance(status, dict):
                errors.append(f"{label}: {endpoint} state-daemon IIO transport status is not an object")
                continue
            for key in (
                "native_iio_transport_daemon",
                "state_daemon_owned_iio_transport",
                "integrated_rf_service_daemon",
                "continuous_queue_worker_lifecycle",
                "state_daemon_iio_transport_control_queue",
                "state_daemon_iio_transport_execution_worker",
                "state_daemon_libiio_execution_owner",
                "service_policy_bound",
                "production_iio_policy",
            ):
                if status.get(key) != 1:
                    errors.append(
                        f"{label}: {endpoint} state-daemon IIO transport {key} is not proven"
                    )
            if status.get("helper_local_iio_daemon_only") != 0:
                errors.append(
                    f"{label}: {endpoint} state-daemon IIO transport still reports helper-only ownership"
                )
            if status.get("helper_local_libiio_execution_only") != 0:
                errors.append(
                    f"{label}: {endpoint} state-daemon IIO transport still reports helper-only libiio execution"
                )
            if (
                status.get("iio_transport_daemon_status_proof")
                != "FIELDMESH_IIO_TRANSPORT_DAEMON_STATUS v1"
            ):
                errors.append(
                    f"{label}: {endpoint} state-daemon IIO transport proof token is invalid"
                )
            if (
                status.get("iio_transport_execution_worker_proof")
                != "FIELDMESH_IIO_TRANSPORT_EXECUTION_WORKER v1"
            ):
                errors.append(
                    f"{label}: {endpoint} state-daemon IIO transport execution proof token is invalid"
                )
    if report.get("iio_bridge_rf_sub_burst_enabled") is not True:
        errors.append(f"{label}: IIO RF sub-burst service must be enabled")
    if report.get("iio_bridge_rf_sub_burst_exercised") is not True:
        errors.append(f"{label}: IIO RF sub-burst service was not exercised")
    sub_burst_size = report.get("iio_bridge_max_frames_per_rf_burst")
    lease_batch_size = report.get("iio_bridge_rf_lease_batch_size")
    lease_high_water = report.get("iio_bridge_rf_lease_batch_high_water")
    burst_high_water = report.get("iio_bridge_rf_burst_batch_high_water")
    sub_burst_deferred = report.get("iio_bridge_rf_sub_burst_deferred_frames")
    sub_burst_preemptions = report.get("iio_bridge_rf_sub_burst_preemption_points")
    sub_burst_reverse_events = report.get(
        "iio_bridge_rf_sub_burst_reverse_service_events"
    )
    if not isinstance(sub_burst_size, int) or sub_burst_size < 1:
        errors.append(f"{label}: IIO RF sub-burst size is missing")
    if not isinstance(lease_batch_size, int) or lease_batch_size < 2:
        errors.append(f"{label}: IIO RF lease batch size must be >= 2")
    elif isinstance(sub_burst_size, int) and sub_burst_size >= lease_batch_size:
        errors.append(f"{label}: IIO RF sub-burst size must be lower than lease batch size")
    if not isinstance(lease_high_water, int) or lease_high_water < 2:
        errors.append(f"{label}: IIO RF lease batch high-water must be >= 2")
    elif isinstance(burst_high_water, int) and lease_high_water <= burst_high_water:
        errors.append(f"{label}: IIO RF lease high-water must exceed RF burst high-water")
    if not isinstance(sub_burst_deferred, int) or sub_burst_deferred < 1:
        errors.append(f"{label}: IIO RF sub-burst deferred-frame evidence is missing")
    if not isinstance(sub_burst_preemptions, int) or sub_burst_preemptions < 1:
        errors.append(f"{label}: IIO RF sub-burst preemption evidence is missing")
    if report.get("iio_bridge_rf_sub_burst_bidirectional_service_exercised") is not True:
        errors.append(f"{label}: IIO RF sub-burst bidirectional service was not exercised")
    if not isinstance(sub_burst_reverse_events, int) or sub_burst_reverse_events < 1:
        errors.append(f"{label}: IIO RF sub-burst reverse-service evidence is missing")
    if report.get("iio_bridge_same_priority_batch") is not True:
        errors.append(f"{label}: IIO same-priority batch evidence must be enabled")
    same_priority_leases = report.get("iio_bridge_same_priority_batch_leases")
    same_priority_drop_stops = report.get(
        "iio_bridge_same_priority_batch_priority_drop_stops"
    )
    if not isinstance(same_priority_leases, int) or same_priority_leases < 1:
        errors.append(f"{label}: IIO same-priority batch lease evidence is missing")
    if (
        isinstance(same_priority_leases, int)
        and isinstance(same_priority_drop_stops, int)
        and same_priority_drop_stops > same_priority_leases
    ):
        errors.append(f"{label}: IIO same-priority priority-drop stops exceed leases")
    if not fair_enabled:
        errors.append(f"{label}: IIO direction fair-service evidence must be enabled")
    if depth < 1:
        errors.append(f"{label}: iio_bridge_source_ack_pipeline_depth must be present")
        return errors
    if batch_size < 1:
        errors.append(f"{label}: iio_bridge_rf_burst_batch_size must be present")
    if fair_enabled:
        fair_budget = report.get("iio_bridge_max_consecutive_direction_batches")
        fair_seen = report.get("iio_bridge_max_consecutive_direction_batches_seen")
        if not isinstance(fair_budget, int) or fair_budget < 1:
            errors.append(f"{label}: IIO direction fair-service budget is missing")
        if not isinstance(fair_seen, int) or fair_seen < 1:
            errors.append(f"{label}: IIO direction fair-service high-water is missing")
        elif isinstance(fair_budget, int) and fair_seen > fair_budget:
            errors.append(f"{label}: IIO direction fair-service high-water exceeded budget")
    if batch_size > 1:
        batch_high_water = report.get("iio_bridge_rf_burst_batch_high_water")
        batch_high_water_by_direction = report.get(
            "iio_bridge_rf_burst_batch_high_water_by_direction"
        )
        if report.get("iio_bridge_rf_burst_batch_exercised") is not True:
            errors.append(f"{label}: IIO RF burst batch_size > 1 was not exercised")
        if not isinstance(batch_high_water, int) or batch_high_water < 2:
            errors.append(f"{label}: IIO RF burst batch high-water must be >= 2")
        elif batch_high_water > batch_size:
            errors.append(f"{label}: IIO RF burst batch high-water exceeded configured size")
        if not isinstance(batch_high_water_by_direction, dict) or not batch_high_water_by_direction:
            errors.append(f"{label}: IIO RF burst batch high-water detail is missing")
        else:
            detail_high_water = max(
                (
                    int(value)
                    for value in batch_high_water_by_direction.values()
                    if isinstance(value, int)
                ),
                default=0,
            )
            if detail_high_water < 2:
                errors.append(f"{label}: IIO RF burst batch high-water detail never exceeded 1")
        if report.get("iio_bridge_same_priority_batch_preemption_exercised") is not True:
            errors.append(
                f"{label}: IIO same-priority batch preemption was not exercised"
            )
        if not isinstance(same_priority_drop_stops, int) or same_priority_drop_stops < 1:
            errors.append(
                f"{label}: IIO same-priority priority-drop stop evidence is missing"
            )
    if depth > 1:
        high_water = report.get("iio_bridge_source_ack_pipeline_high_water")
        max_pending = report.get("iio_bridge_source_ack_pipeline_max_pending")
        latency = report.get("iio_bridge_source_ack_latency_ms")
        max_latency = report.get("iio_bridge_source_ack_max_latency_ms")
        burst_timing = report.get("iio_bridge_rf_burst_timing_ms")
        burst_max = report.get("iio_bridge_rf_burst_max_elapsed_ms")
        burst_live_max = report.get("iio_bridge_rf_burst_live_run_max_elapsed_ms")
        burst_decode_max = report.get("iio_bridge_rf_burst_decode_max_elapsed_ms")
        if report.get("iio_bridge_source_ack_pipeline_active") is not True:
            errors.append(f"{label}: IIO ACK pipeline must be active when depth > 1")
        if report.get("iio_bridge_source_ack_pipeline_exercised") is not True:
            errors.append(f"{label}: IIO ACK pipeline depth > 1 was not exercised")
        if not isinstance(max_pending, int) or max_pending < 2:
            errors.append(f"{label}: IIO ACK pipeline max pending must be >= 2")
        elif max_pending > depth:
            errors.append(f"{label}: IIO ACK pipeline max pending exceeded configured depth")
        if not isinstance(high_water, dict) or not high_water:
            errors.append(f"{label}: IIO ACK pipeline high-water evidence is missing")
        else:
            high_water_max = max(
                (int(value) for value in high_water.values() if isinstance(value, int)),
                default=0,
            )
            if high_water_max < 2:
                errors.append(f"{label}: IIO ACK pipeline high-water evidence never exceeded 1")
        if not isinstance(latency, dict) or not latency:
            errors.append(f"{label}: IIO ACK latency evidence is missing")
        elif not any(
            isinstance(item, dict)
            and isinstance(item.get("completed"), int)
            and item["completed"] > 0
            and isinstance(item.get("max_elapsed_ms"), int)
            and item["max_elapsed_ms"] >= 0
            for item in latency.values()
        ):
            errors.append(f"{label}: IIO ACK latency evidence has no completed ACKs")
        if not isinstance(max_latency, int) or max_latency < 0:
            errors.append(f"{label}: IIO ACK max latency must be >= 0")
        if not isinstance(burst_timing, dict) or not burst_timing:
            errors.append(f"{label}: IIO RF burst timing evidence is missing")
        elif not any(
            isinstance(item, dict)
            and isinstance(item.get("batches"), int)
            and item["batches"] > 0
            and isinstance(item.get("frames"), int)
            and item["frames"] > 0
            and isinstance(item.get("max_elapsed_ms"), int)
            and item["max_elapsed_ms"] >= 0
            for item in burst_timing.values()
        ):
            errors.append(f"{label}: IIO RF burst timing evidence has no completed batches")
        for key, value in (
            ("IIO RF burst max elapsed", burst_max),
            ("IIO RF burst live-run max elapsed", burst_live_max),
            ("IIO RF burst decode max elapsed", burst_decode_max),
        ):
            if not isinstance(value, int) or value < 0:
                errors.append(f"{label}: {key} must be >= 0")
    return errors


def _validate_tcp_final_exchange(report: dict[str, Any], label: str) -> list[str]:
    errors: list[str] = []
    expected_phase = "host_pc" if label == "host_pc_transparent" else "board_to_board"
    exchange = report.get("tcp_final_exchange")
    if not isinstance(exchange, dict) or not exchange:
        return [f"{label}: TCP final-exchange evidence is missing"]
    if exchange.get("event") != "fieldmesh_native_ip_iperf_tcp_final_exchange":
        errors.append(f"{label}: TCP final-exchange event is invalid")
    if exchange.get("phase") != expected_phase:
        errors.append(
            f"{label}: TCP final-exchange phase must be {expected_phase}"
        )
    if exchange.get("ok") is not True:
        errors.append(f"{label}: TCP final-exchange evidence must be ok")
    if not _positive_number(exchange, "client_sent_bytes"):
        errors.append(f"{label}: TCP final-exchange client_sent_bytes must be > 0")
    for key in (
        "initial_client_rc",
        "final_client_rc",
        "iperf_timeout_s",
        "final_exchange_grace_s",
        "queue_quiet_grace_s",
        "queue_quiet_max_consecutive_s",
        "control_drain_s",
    ):
        if not _non_negative_number(exchange, key):
            errors.append(f"{label}: TCP final-exchange {key} must be >= 0")
    if exchange.get("final_client_rc") != 0:
        errors.append(f"{label}: TCP final-exchange final_client_rc must be 0")
    for key in (
        "final_exchange_grace_started",
        "queue_quiet_grace_started",
        "client_preserved_for_control_drain",
        "client_killed_after_control_drain",
        "completed_after_primary_timeout",
        "completed_without_grace",
    ):
        if not isinstance(exchange.get(key), bool):
            errors.append(f"{label}: TCP final-exchange {key} must be boolean")
    if not isinstance(report.get("tcp_final_exchange_grace_started"), bool):
        errors.append(f"{label}: tcp_final_exchange_grace_started must be boolean")
    if not isinstance(report.get("tcp_queue_quiet_grace_started"), bool):
        errors.append(f"{label}: tcp_queue_quiet_grace_started must be boolean")
    if not _non_negative_number(report, "tcp_queue_quiet_max_consecutive_s"):
        errors.append(f"{label}: tcp_queue_quiet_max_consecutive_s must be >= 0")
    if report.get("tcp_final_exchange_grace_started") != exchange.get(
        "final_exchange_grace_started"
    ):
        errors.append(f"{label}: TCP final-exchange grace summary mismatches detail")
    if report.get("tcp_queue_quiet_grace_started") != exchange.get(
        "queue_quiet_grace_started"
    ):
        errors.append(f"{label}: TCP queue-quiet grace summary mismatches detail")
    if report.get("tcp_queue_quiet_max_consecutive_s") != exchange.get(
        "queue_quiet_max_consecutive_s"
    ):
        errors.append(f"{label}: TCP queue-quiet max summary mismatches detail")

    drain = report.get("tcp_control_drain")
    drain_started = report.get("tcp_control_drain_started")
    if not isinstance(drain_started, bool):
        errors.append(f"{label}: tcp_control_drain_started must be boolean")
    if not _non_negative_number(report, "tcp_control_drain_elapsed_s"):
        errors.append(f"{label}: tcp_control_drain_elapsed_s must be >= 0")
    if not isinstance(report.get("tcp_control_drain_ok"), bool):
        errors.append(f"{label}: tcp_control_drain_ok must be boolean")
    if drain_started:
        if not isinstance(drain, dict) or not drain:
            errors.append(f"{label}: TCP control-drain detail is missing")
        else:
            if drain.get("event") != "fieldmesh_native_ip_iperf_tcp_control_drain":
                errors.append(f"{label}: TCP control-drain event is invalid")
            if drain.get("phase") != expected_phase:
                errors.append(
                    f"{label}: TCP control-drain phase must be {expected_phase}"
                )
            if drain.get("ok") is not True:
                errors.append(f"{label}: TCP control-drain evidence must be ok")
            if not _positive_number(drain, "client_sent_bytes_before_timeout"):
                errors.append(
                    f"{label}: TCP control-drain client_sent_bytes_before_timeout must be > 0"
                )
            if not _non_negative_number(drain, "elapsed_s"):
                errors.append(f"{label}: TCP control-drain elapsed_s must be >= 0")
            if report.get("tcp_control_drain_elapsed_s") != drain.get("elapsed_s"):
                errors.append(f"{label}: TCP control-drain elapsed summary mismatches detail")
            if report.get("tcp_control_drain_ok") != drain.get("ok"):
                errors.append(f"{label}: TCP control-drain ok summary mismatches detail")
    elif drain not in ({}, None):
        errors.append(f"{label}: TCP control-drain detail exists but started=false")
    return errors


def _reject_common(report: dict[str, Any], label: str) -> list[str]:
    errors: list[str] = []
    if report.get("event") != "fieldmesh_two_board_native_ip_iperf":
        errors.append(f"{label}: unexpected event {report.get('event')!r}")
    if report.get("ok") is not True:
        errors.append(f"{label}: ok must be true")
    if report.get("feature") not in (None, "native_ip"):
        errors.append(f"{label}: feature must be native_ip")
    if report.get("transport") != "real_rf_phy":
        errors.append(f"{label}: transport must be real_rf_phy")
    if not _is_true(report.get("rf_phy_tx_rx_verified")):
        errors.append(f"{label}: rf_phy_tx_rx_verified must be true")
    if report.get("diagnostic_bridge") in (True, 1, "1", "true"):
        errors.append(f"{label}: diagnostic bridge evidence is not production RF")
    if report.get("transport") == "daemon_rf_driver_queue_bridge":
        errors.append(f"{label}: daemon RF-worker bridge is diagnostic only")
    if report.get("uses_inter_board_ip_routing") in (True, 1, "1", "true"):
        errors.append(f"{label}: inter-board host-IP routing is not transparent MAC evidence")
    if not _is_true(report.get("production_evidence")):
        errors.append(f"{label}: production_evidence must be true")
    if not _is_true(report.get("app_verified_real_rf")):
        errors.append(f"{label}: app_verified_real_rf must be true")
    errors.extend(_validate_iio_ack_pipeline(report, label))
    errors.extend(_validate_tcp_final_exchange(report, label))
    return errors


def _validate_board(report: dict[str, Any]) -> list[str]:
    errors = _reject_common(report, "board_to_board")
    if report.get("iperf_layer") not in (None, "board_to_board"):
        errors.append("board_to_board: iperf_layer must be board_to_board")
    if report.get("host_pc_case_requested") is not False:
        errors.append("board_to_board: host_pc_case_requested must be false")
    if report.get("host_pc_iperf") not in (False, 0, None):
        errors.append("board_to_board: host_pc_iperf must be false")
    if report.get("board_to_board_iperf") is not True:
        errors.append("board_to_board: board_to_board_iperf must be true")
    if not _positive_number(report, "tcp_bytes"):
        errors.append("board_to_board: tcp_bytes must be > 0")
    if not _positive_number(report, "tcp_bits_per_second"):
        errors.append("board_to_board: tcp_bits_per_second must be > 0")
    if not _positive_number(report, "udp_bits_per_second"):
        errors.append("board_to_board: udp_bits_per_second must be > 0")
    if not _positive_number(report, "udp_bytes"):
        errors.append("board_to_board: udp_bytes must be > 0")
    errors.extend(_require_iperf_quality(report, "board_to_board"))
    return errors


def _validate_host(report: dict[str, Any]) -> list[str]:
    errors = _reject_common(report, "host_pc_transparent")
    if report.get("iperf_layer") != "host_pc_transparent":
        errors.append("host_pc_transparent: iperf_layer must be host_pc_transparent")
    if report.get("host_pc_case_requested") is not True:
        errors.append("host_pc_transparent: host_pc_case_requested must be true")
    if report.get("host_pc_iperf") is not True:
        errors.append("host_pc_transparent: host_pc_iperf must be true")
    if report.get("host_originated_traffic") is not True:
        errors.append("host_pc_transparent: host_originated_traffic must be true")
    if report.get("uses_ssh_launched_board_client") in (True, 1, "1", "true"):
        errors.append("host_pc_transparent: host traffic must not be SSH-launched on a board")
    if not _positive_number(report, "host_tcp_bytes"):
        errors.append("host_pc_transparent: host_tcp_bytes must be > 0")
    if not _positive_number(report, "host_tcp_bits_per_second"):
        errors.append("host_pc_transparent: host_tcp_bits_per_second must be > 0")
    if not _positive_number(report, "host_udp_bits_per_second"):
        errors.append("host_pc_transparent: host_udp_bits_per_second must be > 0")
    if not _positive_number(report, "host_udp_bytes"):
        errors.append("host_pc_transparent: host_udp_bytes must be > 0")
    errors.extend(
        _require_iperf_quality(
            report,
            "host_pc_transparent",
            tcp_prefix="host_",
            udp_prefix="host_",
        )
    )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--board-to-board-report", required=True)
    parser.add_argument("--host-pc-report", required=True)
    parser.add_argument("--output", default="")
    args = parser.parse_args()

    board_path = Path(args.board_to_board_report)
    host_path = Path(args.host_pc_report)
    board = _load_report(board_path)
    host = _load_report(host_path)

    errors = _validate_board(board) + _validate_host(host)
    board_requires_ack_pipeline = (
        _is_true(board.get("iio_rf_bridge"))
        and isinstance(board.get("iio_bridge_source_ack_pipeline_depth"), int)
        and board.get("iio_bridge_source_ack_pipeline_depth") > 1
    )
    host_requires_ack_pipeline = (
        _is_true(host.get("iio_rf_bridge"))
        and isinstance(host.get("iio_bridge_source_ack_pipeline_depth"), int)
        and host.get("iio_bridge_source_ack_pipeline_depth") > 1
    )
    board_requires_burst_batch = (
        _is_true(board.get("iio_rf_bridge"))
        and isinstance(board.get("iio_bridge_rf_burst_batch_size"), int)
        and board.get("iio_bridge_rf_burst_batch_size") > 1
    )
    host_requires_burst_batch = (
        _is_true(host.get("iio_rf_bridge"))
        and isinstance(host.get("iio_bridge_rf_burst_batch_size"), int)
        and host.get("iio_bridge_rf_burst_batch_size") > 1
    )
    board_requires_direction_fair_service = (
        _is_true(board.get("iio_rf_bridge"))
        and board.get("iio_bridge_direction_fair_service_enabled") is True
    )
    host_requires_direction_fair_service = (
        _is_true(host.get("iio_rf_bridge"))
        and host.get("iio_bridge_direction_fair_service_enabled") is True
    )
    board_requires_same_priority_batch = _is_true(board.get("iio_rf_bridge"))
    host_requires_same_priority_batch = _is_true(host.get("iio_rf_bridge"))
    board_requires_c_policy = _is_true(board.get("iio_rf_bridge"))
    host_requires_c_policy = _is_true(host.get("iio_rf_bridge"))
    report = {
        "event": "fieldmesh_native_ip_iperf_evidence",
        "ok": not errors,
        "feature": "native_ip",
        "transport": "real_rf_phy" if not errors else "invalid",
        "uses_inter_board_ip_routing": False,
        "rf_phy_tx_rx_verified": not errors,
        "app_verified_real_rf": not errors,
        "feature_ok": not errors,
        "board_to_board_real_rf_iperf": not _validate_board(board),
        "host_pc_transparent_real_rf_iperf": not _validate_host(host),
        "requires_both_layers": True,
        "requires_iio_ack_pipeline_evidence": bool(
            board_requires_ack_pipeline or host_requires_ack_pipeline
        ),
        "requires_iio_rf_burst_batch_evidence": bool(
            board_requires_burst_batch or host_requires_burst_batch
        ),
        "requires_iio_direction_fair_service_evidence": bool(
            board_requires_direction_fair_service
            or host_requires_direction_fair_service
        ),
        "requires_iio_same_priority_batch_evidence": bool(
            board_requires_same_priority_batch or host_requires_same_priority_batch
        ),
        "requires_iio_hybrid_lease_priority": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_persistent_burst_helper": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_native_iio_burst_worker": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_native_iio_burst_worker_lifecycle": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_native_iio_burst_transport_worker": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_native_iio_burst_transport_session": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_native_iio_burst_transport_service_loop": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_native_iio_burst_transport_scheduler": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_native_iio_burst_transport_autonomous_loop": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_native_iio_burst_transport_background_daemon": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_native_iio_burst_integrated_rf_service_daemon": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_native_iio_burst_state_daemon_transport_queue": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_native_iio_burst_state_daemon_transport_lifecycle": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_native_iio_burst_state_daemon_modem_profile": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_state_daemon_iio_transport": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_in_burst_priority_preemption": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_rf_sub_burst_evidence": bool(
            _is_true(board.get("iio_rf_bridge")) or _is_true(host.get("iio_rf_bridge"))
        ),
        "requires_iio_rf_service_policy_proof": bool(
            board_requires_c_policy or host_requires_c_policy
        ),
        "requires_iio_native_rf_service_worker_proof": bool(
            board_requires_c_policy or host_requires_c_policy
        ),
        "requires_iio_native_service_burst_leases": bool(
            board_requires_c_policy or host_requires_c_policy
        ),
        "requires_iio_native_service_loop_tick": bool(
            board_requires_c_policy or host_requires_c_policy
        ),
        "requires_iio_native_cross_daemon_transport_loop": bool(
            board_requires_c_policy or host_requires_c_policy
        ),
        "requires_iio_native_service_loop_worker": bool(
            board_requires_c_policy or host_requires_c_policy
        ),
        "requires_iio_native_direction_scheduler": bool(
            board_requires_c_policy or host_requires_c_policy
        ),
        "requires_iio_native_bidirectional_direction_decision": bool(
            board_requires_c_policy or host_requires_c_policy
        ),
        "requires_tcp_final_exchange_evidence": True,
        "board_iio_rf_service_policy_proven": (
            True
            if not board_requires_c_policy
            else board.get("iio_bridge_rf_service_policy_proven") is True
        ),
        "host_iio_rf_service_policy_proven": (
            True
            if not host_requires_c_policy
            else host.get("iio_bridge_rf_service_policy_proven") is True
        ),
        "board_iio_rf_service_policy_native_c": board.get(
            "iio_bridge_rf_service_policy_native_c"
        ),
        "host_iio_rf_service_policy_native_c": host.get(
            "iio_bridge_rf_service_policy_native_c"
        ),
        "board_iio_rf_service_policy_production_iio": board.get(
            "iio_bridge_rf_service_policy_production_iio"
        ),
        "host_iio_rf_service_policy_production_iio": host.get(
            "iio_bridge_rf_service_policy_production_iio"
        ),
        "board_iio_rf_service_policy_lease_batch_frames": board.get(
            "iio_bridge_rf_service_policy_lease_batch_frames"
        ),
        "host_iio_rf_service_policy_lease_batch_frames": host.get(
            "iio_bridge_rf_service_policy_lease_batch_frames"
        ),
        "board_iio_rf_service_policy_max_frames_per_rf_burst": board.get(
            "iio_bridge_rf_service_policy_max_frames_per_rf_burst"
        ),
        "host_iio_rf_service_policy_max_frames_per_rf_burst": host.get(
            "iio_bridge_rf_service_policy_max_frames_per_rf_burst"
        ),
        "board_iio_rf_service_policy_requires_reverse_service": board.get(
            "iio_bridge_rf_service_policy_requires_reverse_service"
        ),
        "host_iio_rf_service_policy_requires_reverse_service": host.get(
            "iio_bridge_rf_service_policy_requires_reverse_service"
        ),
        "board_iio_rf_service_policy_lease_priority": board.get(
            "iio_bridge_rf_service_policy_lease_priority"
        ),
        "host_iio_rf_service_policy_lease_priority": host.get(
            "iio_bridge_rf_service_policy_lease_priority"
        ),
        "board_iio_rf_service_policy_in_burst_priority_preemption": board.get(
            "iio_bridge_rf_service_policy_in_burst_priority_preemption"
        ),
        "host_iio_rf_service_policy_in_burst_priority_preemption": host.get(
            "iio_bridge_rf_service_policy_in_burst_priority_preemption"
        ),
        "board_iio_native_rf_service_worker_proven": (
            True
            if not board_requires_c_policy
            else board.get("iio_bridge_native_rf_service_worker_proven") is True
        ),
        "host_iio_native_rf_service_worker_proven": (
            True
            if not host_requires_c_policy
            else host.get("iio_bridge_native_rf_service_worker_proven") is True
        ),
        "board_iio_native_rf_service_worker_status": board.get(
            "iio_bridge_native_rf_service_worker_status"
        ) or {},
        "host_iio_native_rf_service_worker_status": host.get(
            "iio_bridge_native_rf_service_worker_status"
        ) or {},
        "board_iio_native_service_burst_leases_enabled": (
            True
            if not board_requires_c_policy
            else board.get("iio_bridge_native_service_burst_leases_enabled") is True
        ),
        "host_iio_native_service_burst_leases_enabled": (
            True
            if not host_requires_c_policy
            else host.get("iio_bridge_native_service_burst_leases_enabled") is True
        ),
        "board_iio_native_service_burst_leases": board.get(
            "iio_bridge_native_service_burst_leases"
        ),
        "host_iio_native_service_burst_leases": host.get(
            "iio_bridge_native_service_burst_leases"
        ),
        "board_iio_native_service_loop_tick_enabled": (
            True
            if not board_requires_c_policy
            else board.get("iio_bridge_native_service_loop_tick_enabled") is True
        ),
        "host_iio_native_service_loop_tick_enabled": (
            True
            if not host_requires_c_policy
            else host.get("iio_bridge_native_service_loop_tick_enabled") is True
        ),
        "board_iio_native_service_loop_tick_proven": (
            True
            if not board_requires_c_policy
            else board.get("iio_bridge_native_service_loop_tick_proven") is True
        ),
        "host_iio_native_service_loop_tick_proven": (
            True
            if not host_requires_c_policy
            else host.get("iio_bridge_native_service_loop_tick_proven") is True
        ),
        "board_iio_native_service_loop_ticks": board.get(
            "iio_bridge_native_service_loop_ticks"
        ),
        "host_iio_native_service_loop_ticks": host.get(
            "iio_bridge_native_service_loop_ticks"
        ),
        "board_iio_native_service_loop_tick_skips": board.get(
            "iio_bridge_native_service_loop_tick_skips"
        ),
        "host_iio_native_service_loop_tick_skips": host.get(
            "iio_bridge_native_service_loop_tick_skips"
        ),
        "board_iio_native_service_loop_tick_status": board.get(
            "iio_bridge_native_service_loop_tick_status"
        ) or {},
        "host_iio_native_service_loop_tick_status": host.get(
            "iio_bridge_native_service_loop_tick_status"
        ) or {},
        "board_iio_native_cross_daemon_transport_loop_required": (
            True
            if not board_requires_c_policy
            else board.get("iio_bridge_native_cross_daemon_transport_loop_required")
            is True
        ),
        "host_iio_native_cross_daemon_transport_loop_required": (
            True
            if not host_requires_c_policy
            else host.get("iio_bridge_native_cross_daemon_transport_loop_required")
            is True
        ),
        "board_iio_native_cross_daemon_transport_loop_proven": (
            True
            if not board_requires_c_policy
            else board.get("iio_bridge_native_cross_daemon_transport_loop_proven")
            is True
        ),
        "host_iio_native_cross_daemon_transport_loop_proven": (
            True
            if not host_requires_c_policy
            else host.get("iio_bridge_native_cross_daemon_transport_loop_proven")
            is True
        ),
        "board_iio_native_cross_daemon_transport_loop_ticks": board.get(
            "iio_bridge_native_cross_daemon_transport_loop_ticks"
        ),
        "host_iio_native_cross_daemon_transport_loop_ticks": host.get(
            "iio_bridge_native_cross_daemon_transport_loop_ticks"
        ),
        "board_iio_native_service_loop_worker_required": (
            True
            if not board_requires_c_policy
            else board.get("iio_bridge_native_service_loop_worker_required") is True
        ),
        "host_iio_native_service_loop_worker_required": (
            True
            if not host_requires_c_policy
            else host.get("iio_bridge_native_service_loop_worker_required") is True
        ),
        "board_iio_native_service_loop_worker_proven": (
            True
            if not board_requires_c_policy
            else board.get("iio_bridge_native_service_loop_worker_proven") is True
        ),
        "host_iio_native_service_loop_worker_proven": (
            True
            if not host_requires_c_policy
            else host.get("iio_bridge_native_service_loop_worker_proven") is True
        ),
        "board_iio_native_service_loop_worker_starts": board.get(
            "iio_bridge_native_service_loop_worker_starts"
        ),
        "host_iio_native_service_loop_worker_starts": host.get(
            "iio_bridge_native_service_loop_worker_starts"
        ),
        "board_iio_native_service_loop_worker_status_polls": board.get(
            "iio_bridge_native_service_loop_worker_status_polls"
        ),
        "host_iio_native_service_loop_worker_status_polls": host.get(
            "iio_bridge_native_service_loop_worker_status_polls"
        ),
        "board_iio_native_service_loop_worker_status": board.get(
            "iio_bridge_native_service_loop_worker_status"
        ) or {},
        "host_iio_native_service_loop_worker_status": host.get(
            "iio_bridge_native_service_loop_worker_status"
        ) or {},
        "board_iio_native_direction_scheduler_enabled": (
            True
            if not board_requires_c_policy
            else board.get("iio_bridge_native_direction_scheduler_enabled") is True
        ),
        "host_iio_native_direction_scheduler_enabled": (
            True
            if not host_requires_c_policy
            else host.get("iio_bridge_native_direction_scheduler_enabled") is True
        ),
        "board_iio_native_direction_scheduler_proven": (
            True
            if not board_requires_c_policy
            else board.get("iio_bridge_native_direction_scheduler_proven") is True
        ),
        "host_iio_native_direction_scheduler_proven": (
            True
            if not host_requires_c_policy
            else host.get("iio_bridge_native_direction_scheduler_proven") is True
        ),
        "board_iio_native_direction_scheduler_status_polls": board.get(
            "iio_bridge_native_direction_scheduler_status_polls"
        ),
        "host_iio_native_direction_scheduler_status_polls": host.get(
            "iio_bridge_native_direction_scheduler_status_polls"
        ),
        "board_iio_native_direction_scheduler_status": board.get(
            "iio_bridge_native_direction_scheduler_status"
        ) or {},
        "host_iio_native_direction_scheduler_status": host.get(
            "iio_bridge_native_direction_scheduler_status"
        ) or {},
        "board_iio_native_bidirectional_direction_decision_enabled": (
            True
            if not board_requires_c_policy
            else board.get(
                "iio_bridge_native_bidirectional_direction_decision_enabled"
            )
            is True
        ),
        "host_iio_native_bidirectional_direction_decision_enabled": (
            True
            if not host_requires_c_policy
            else host.get(
                "iio_bridge_native_bidirectional_direction_decision_enabled"
            )
            is True
        ),
        "board_iio_native_bidirectional_direction_decision_proven": (
            True
            if not board_requires_c_policy
            else board.get(
                "iio_bridge_native_bidirectional_direction_decision_proven"
            )
            is True
        ),
        "host_iio_native_bidirectional_direction_decision_proven": (
            True
            if not host_requires_c_policy
            else host.get(
                "iio_bridge_native_bidirectional_direction_decision_proven"
            )
            is True
        ),
        "board_iio_native_bidirectional_direction_decision_polls": board.get(
            "iio_bridge_native_bidirectional_direction_decision_polls"
        ),
        "host_iio_native_bidirectional_direction_decision_polls": host.get(
            "iio_bridge_native_bidirectional_direction_decision_polls"
        ),
        "board_iio_native_bidirectional_direction_decision_status": board.get(
            "iio_bridge_native_bidirectional_direction_decision_status"
        ) or {},
        "host_iio_native_bidirectional_direction_decision_status": host.get(
            "iio_bridge_native_bidirectional_direction_decision_status"
        ) or {},
        "board_iio_ack_pipeline_exercised": (
            True
            if not board_requires_ack_pipeline
            else board.get("iio_bridge_source_ack_pipeline_exercised") is True
        ),
        "host_iio_ack_pipeline_exercised": (
            True
            if not host_requires_ack_pipeline
            else host.get("iio_bridge_source_ack_pipeline_exercised") is True
        ),
        "board_iio_rf_burst_batch_exercised": (
            True
            if not board_requires_burst_batch
            else board.get("iio_bridge_rf_burst_batch_exercised") is True
        ),
        "host_iio_rf_burst_batch_exercised": (
            True
            if not host_requires_burst_batch
            else host.get("iio_bridge_rf_burst_batch_exercised") is True
        ),
        "board_iio_direction_fair_service_within_budget": (
            True
            if not board_requires_direction_fair_service
            else (
                isinstance(board.get("iio_bridge_max_consecutive_direction_batches"), int)
                and isinstance(board.get("iio_bridge_max_consecutive_direction_batches_seen"), int)
                and board.get("iio_bridge_max_consecutive_direction_batches_seen")
                <= board.get("iio_bridge_max_consecutive_direction_batches")
            )
        ),
        "host_iio_direction_fair_service_within_budget": (
            True
            if not host_requires_direction_fair_service
            else (
                isinstance(host.get("iio_bridge_max_consecutive_direction_batches"), int)
                and isinstance(host.get("iio_bridge_max_consecutive_direction_batches_seen"), int)
                and host.get("iio_bridge_max_consecutive_direction_batches_seen")
                <= host.get("iio_bridge_max_consecutive_direction_batches")
            )
        ),
        "board_iio_same_priority_batch_enabled": (
            True
            if not board_requires_same_priority_batch
            else board.get("iio_bridge_same_priority_batch") is True
        ),
        "host_iio_same_priority_batch_enabled": (
            True
            if not host_requires_same_priority_batch
            else host.get("iio_bridge_same_priority_batch") is True
        ),
        "board_iio_same_priority_batch_preemption_exercised": (
            True
            if not board_requires_burst_batch
            else board.get("iio_bridge_same_priority_batch_preemption_exercised") is True
        ),
        "host_iio_same_priority_batch_preemption_exercised": (
            True
            if not host_requires_burst_batch
            else host.get("iio_bridge_same_priority_batch_preemption_exercised") is True
        ),
        "board_iio_bridge_same_priority_batch_leases": board.get(
            "iio_bridge_same_priority_batch_leases"
        ),
        "host_iio_bridge_same_priority_batch_leases": host.get(
            "iio_bridge_same_priority_batch_leases"
        ),
        "board_iio_bridge_same_priority_batch_priority_drop_stops": board.get(
            "iio_bridge_same_priority_batch_priority_drop_stops"
        ),
        "host_iio_bridge_same_priority_batch_priority_drop_stops": host.get(
            "iio_bridge_same_priority_batch_priority_drop_stops"
        ),
        "board_iio_bridge_lease_priority": board.get("iio_bridge_lease_priority"),
        "host_iio_bridge_lease_priority": host.get("iio_bridge_lease_priority"),
        "board_iio_bridge_persistent_burst_helper": board.get(
            "iio_bridge_persistent_burst_helper"
        ),
        "host_iio_bridge_persistent_burst_helper": host.get(
            "iio_bridge_persistent_burst_helper"
        ),
        "board_iio_native_iio_burst_worker_proven": board.get(
            "iio_bridge_native_iio_burst_worker_proven"
        ),
        "host_iio_native_iio_burst_worker_proven": host.get(
            "iio_bridge_native_iio_burst_worker_proven"
        ),
        "board_iio_native_iio_burst_worker_invocations": board.get(
            "iio_bridge_native_iio_burst_worker_invocations"
        ),
        "host_iio_native_iio_burst_worker_invocations": host.get(
            "iio_bridge_native_iio_burst_worker_invocations"
        ),
        "board_iio_native_iio_burst_worker_lifecycle_proven": board.get(
            "iio_bridge_native_iio_burst_worker_lifecycle_proven"
        ),
        "host_iio_native_iio_burst_worker_lifecycle_proven": host.get(
            "iio_bridge_native_iio_burst_worker_lifecycle_proven"
        ),
        "board_iio_native_iio_burst_worker_lifecycle_invocations": board.get(
            "iio_bridge_native_iio_burst_worker_lifecycle_invocations"
        ),
        "host_iio_native_iio_burst_worker_lifecycle_invocations": host.get(
            "iio_bridge_native_iio_burst_worker_lifecycle_invocations"
        ),
        "board_iio_native_iio_burst_transport_worker_proven": board.get(
            "iio_bridge_native_iio_burst_transport_worker_proven"
        ),
        "host_iio_native_iio_burst_transport_worker_proven": host.get(
            "iio_bridge_native_iio_burst_transport_worker_proven"
        ),
        "board_iio_native_iio_burst_transport_worker_invocations": board.get(
            "iio_bridge_native_iio_burst_transport_worker_invocations"
        ),
        "host_iio_native_iio_burst_transport_worker_invocations": host.get(
            "iio_bridge_native_iio_burst_transport_worker_invocations"
        ),
        "board_iio_native_iio_burst_transport_session_proven": board.get(
            "iio_bridge_native_iio_burst_transport_session_proven"
        ),
        "host_iio_native_iio_burst_transport_session_proven": host.get(
            "iio_bridge_native_iio_burst_transport_session_proven"
        ),
        "board_iio_native_iio_burst_transport_session_invocations": board.get(
            "iio_bridge_native_iio_burst_transport_session_invocations"
        ),
        "host_iio_native_iio_burst_transport_session_invocations": host.get(
            "iio_bridge_native_iio_burst_transport_session_invocations"
        ),
        "board_iio_native_iio_burst_transport_service_loop_proven": board.get(
            "iio_bridge_native_iio_burst_transport_service_loop_proven"
        ),
        "host_iio_native_iio_burst_transport_service_loop_proven": host.get(
            "iio_bridge_native_iio_burst_transport_service_loop_proven"
        ),
        "board_iio_native_iio_burst_transport_service_loop_invocations": board.get(
            "iio_bridge_native_iio_burst_transport_service_loop_invocations"
        ),
        "host_iio_native_iio_burst_transport_service_loop_invocations": host.get(
            "iio_bridge_native_iio_burst_transport_service_loop_invocations"
        ),
        "board_iio_native_iio_burst_transport_scheduler_proven": board.get(
            "iio_bridge_native_iio_burst_transport_scheduler_proven"
        ),
        "host_iio_native_iio_burst_transport_scheduler_proven": host.get(
            "iio_bridge_native_iio_burst_transport_scheduler_proven"
        ),
        "board_iio_native_iio_burst_transport_scheduler_invocations": board.get(
            "iio_bridge_native_iio_burst_transport_scheduler_invocations"
        ),
        "host_iio_native_iio_burst_transport_scheduler_invocations": host.get(
            "iio_bridge_native_iio_burst_transport_scheduler_invocations"
        ),
        "board_iio_native_iio_burst_transport_autonomous_loop_proven": board.get(
            "iio_bridge_native_iio_burst_transport_autonomous_loop_proven"
        ),
        "host_iio_native_iio_burst_transport_autonomous_loop_proven": host.get(
            "iio_bridge_native_iio_burst_transport_autonomous_loop_proven"
        ),
        "board_iio_native_iio_burst_transport_autonomous_loop_invocations": board.get(
            "iio_bridge_native_iio_burst_transport_autonomous_loop_invocations"
        ),
        "host_iio_native_iio_burst_transport_autonomous_loop_invocations": host.get(
            "iio_bridge_native_iio_burst_transport_autonomous_loop_invocations"
        ),
        "board_iio_native_iio_burst_transport_background_daemon_proven": board.get(
            "iio_bridge_native_iio_burst_transport_background_daemon_proven"
        ),
        "host_iio_native_iio_burst_transport_background_daemon_proven": host.get(
            "iio_bridge_native_iio_burst_transport_background_daemon_proven"
        ),
        "board_iio_native_iio_burst_transport_background_daemon_invocations": board.get(
            "iio_bridge_native_iio_burst_transport_background_daemon_invocations"
        ),
        "host_iio_native_iio_burst_transport_background_daemon_invocations": host.get(
            "iio_bridge_native_iio_burst_transport_background_daemon_invocations"
        ),
        "board_iio_native_iio_burst_integrated_rf_service_daemon_proven": board.get(
            "iio_bridge_native_iio_burst_integrated_rf_service_daemon_proven"
        ),
        "host_iio_native_iio_burst_integrated_rf_service_daemon_proven": host.get(
            "iio_bridge_native_iio_burst_integrated_rf_service_daemon_proven"
        ),
        "board_iio_native_iio_burst_integrated_rf_service_daemon_invocations": board.get(
            "iio_bridge_native_iio_burst_integrated_rf_service_daemon_invocations"
        ),
        "host_iio_native_iio_burst_integrated_rf_service_daemon_invocations": host.get(
            "iio_bridge_native_iio_burst_integrated_rf_service_daemon_invocations"
        ),
        "board_iio_native_iio_burst_state_daemon_transport_queue_proven": board.get(
            "iio_bridge_native_iio_burst_state_daemon_transport_queue_proven"
        ),
        "host_iio_native_iio_burst_state_daemon_transport_queue_proven": host.get(
            "iio_bridge_native_iio_burst_state_daemon_transport_queue_proven"
        ),
        "board_iio_native_iio_burst_state_daemon_transport_queue_invocations": board.get(
            "iio_bridge_native_iio_burst_state_daemon_transport_queue_invocations"
        ),
        "host_iio_native_iio_burst_state_daemon_transport_queue_invocations": host.get(
            "iio_bridge_native_iio_burst_state_daemon_transport_queue_invocations"
        ),
        "board_iio_native_iio_burst_state_daemon_transport_lifecycle_proven": board.get(
            "iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_proven"
        ),
        "host_iio_native_iio_burst_state_daemon_transport_lifecycle_proven": host.get(
            "iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_proven"
        ),
        "board_iio_native_iio_burst_state_daemon_transport_lifecycle_invocations": board.get(
            "iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_invocations"
        ),
        "host_iio_native_iio_burst_state_daemon_transport_lifecycle_invocations": host.get(
            "iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_invocations"
        ),
        "board_iio_native_iio_burst_state_daemon_modem_profile_proven": board.get(
            "iio_bridge_native_iio_burst_state_daemon_modem_profile_proven"
        ),
        "host_iio_native_iio_burst_state_daemon_modem_profile_proven": host.get(
            "iio_bridge_native_iio_burst_state_daemon_modem_profile_proven"
        ),
        "board_iio_native_iio_burst_state_daemon_modem_profile_invocations": board.get(
            "iio_bridge_native_iio_burst_state_daemon_modem_profile_invocations"
        ),
        "host_iio_native_iio_burst_state_daemon_modem_profile_invocations": host.get(
            "iio_bridge_native_iio_burst_state_daemon_modem_profile_invocations"
        ),
        "board_iio_state_daemon_iio_transport_proven": board.get(
            "iio_bridge_state_daemon_iio_transport_proven"
        ),
        "host_iio_state_daemon_iio_transport_proven": host.get(
            "iio_bridge_state_daemon_iio_transport_proven"
        ),
        "board_iio_state_daemon_iio_transport_status_polls": board.get(
            "iio_bridge_state_daemon_iio_transport_status_polls"
        ),
        "host_iio_state_daemon_iio_transport_status_polls": host.get(
            "iio_bridge_state_daemon_iio_transport_status_polls"
        ),
        "board_iio_state_daemon_iio_transport_enqueue_proven": board.get(
            "iio_bridge_state_daemon_iio_transport_enqueue_proven"
        ),
        "host_iio_state_daemon_iio_transport_enqueue_proven": host.get(
            "iio_bridge_state_daemon_iio_transport_enqueue_proven"
        ),
        "board_iio_state_daemon_iio_transport_enqueues": board.get(
            "iio_bridge_state_daemon_iio_transport_enqueues"
        ),
        "host_iio_state_daemon_iio_transport_enqueues": host.get(
            "iio_bridge_state_daemon_iio_transport_enqueues"
        ),
        "board_iio_state_daemon_iio_transport_drains": board.get(
            "iio_bridge_state_daemon_iio_transport_drains"
        ),
        "host_iio_state_daemon_iio_transport_drains": host.get(
            "iio_bridge_state_daemon_iio_transport_drains"
        ),
        "board_iio_state_daemon_iio_transport_execution_worker_runs": board.get(
            "iio_bridge_state_daemon_iio_transport_execution_worker_runs"
        ),
        "host_iio_state_daemon_iio_transport_execution_worker_runs": host.get(
            "iio_bridge_state_daemon_iio_transport_execution_worker_runs"
        ),
        "board_iio_bridge_sample_rate_hz": board.get("iio_bridge_sample_rate_hz"),
        "host_iio_bridge_sample_rate_hz": host.get("iio_bridge_sample_rate_hz"),
        "board_iio_bridge_rf_bandwidth_hz": board.get("iio_bridge_rf_bandwidth_hz"),
        "host_iio_bridge_rf_bandwidth_hz": host.get("iio_bridge_rf_bandwidth_hz"),
        "board_iio_bridge_phy_raw_bitrate_bps": board.get("iio_bridge_phy_raw_bitrate_bps"),
        "host_iio_bridge_phy_raw_bitrate_bps": host.get("iio_bridge_phy_raw_bitrate_bps"),
        "board_iio_bridge_phy_primary_raw_bitrate_bps": board.get(
            "iio_bridge_phy_primary_raw_bitrate_bps"
        ),
        "host_iio_bridge_phy_primary_raw_bitrate_bps": host.get(
            "iio_bridge_phy_primary_raw_bitrate_bps"
        ),
        "board_iio_bridge_phy_min_raw_bitrate_bps": board.get(
            "iio_bridge_phy_min_raw_bitrate_bps"
        ),
        "host_iio_bridge_phy_min_raw_bitrate_bps": host.get(
            "iio_bridge_phy_min_raw_bitrate_bps"
        ),
        "board_iio_bridge_phy_effective_raw_bitrate_bps": board.get(
            "iio_bridge_phy_effective_raw_bitrate_bps"
        ),
        "host_iio_bridge_phy_effective_raw_bitrate_bps": host.get(
            "iio_bridge_phy_effective_raw_bitrate_bps"
        ),
        "board_iio_bridge_phy_min_effective_raw_bitrate_bps": board.get(
            "iio_bridge_phy_min_effective_raw_bitrate_bps"
        ),
        "host_iio_bridge_phy_min_effective_raw_bitrate_bps": host.get(
            "iio_bridge_phy_min_effective_raw_bitrate_bps"
        ),
        "board_iio_bridge_phy_fast_primary_decode_proven": board.get(
            "iio_bridge_phy_fast_primary_decode_proven"
        ),
        "host_iio_bridge_phy_fast_primary_decode_proven": host.get(
            "iio_bridge_phy_fast_primary_decode_proven"
        ),
        "board_iio_bridge_phy_modem_retry_used": board.get(
            "iio_bridge_phy_modem_retry_used"
        ),
        "host_iio_bridge_phy_modem_retry_used": host.get(
            "iio_bridge_phy_modem_retry_used"
        ),
        "board_iio_adaptive_modem_profile_policy_proven": board.get(
            "iio_bridge_adaptive_modem_profile_policy_proven"
        ),
        "host_iio_adaptive_modem_profile_policy_proven": host.get(
            "iio_bridge_adaptive_modem_profile_policy_proven"
        ),
        "board_iio_fast_primary_min_raw_bitrate_bps": board.get(
            "iio_bridge_fast_primary_min_raw_bitrate_bps"
        ),
        "host_iio_fast_primary_min_raw_bitrate_bps": host.get(
            "iio_bridge_fast_primary_min_raw_bitrate_bps"
        ),
        "board_iio_fast_primary_decision": board.get(
            "iio_bridge_fast_primary_decision"
        ),
        "host_iio_fast_primary_decision": host.get(
            "iio_bridge_fast_primary_decision"
        ),
        "board_iio_retry_fallback_decision": board.get(
            "iio_bridge_retry_fallback_decision"
        ),
        "host_iio_retry_fallback_decision": host.get(
            "iio_bridge_retry_fallback_decision"
        ),
        "board_iio_adaptive_modem_profile_measured_quality_policy": board.get(
            "iio_bridge_adaptive_modem_profile_measured_quality_policy"
        ),
        "host_iio_adaptive_modem_profile_measured_quality_policy": host.get(
            "iio_bridge_adaptive_modem_profile_measured_quality_policy"
        ),
        "board_iio_fast_primary_min_decode_attempts": board.get(
            "iio_bridge_fast_primary_min_decode_attempts"
        ),
        "host_iio_fast_primary_min_decode_attempts": host.get(
            "iio_bridge_fast_primary_min_decode_attempts"
        ),
        "board_iio_fast_primary_quality_decision": board.get(
            "iio_bridge_fast_primary_quality_decision"
        ),
        "host_iio_fast_primary_quality_decision": host.get(
            "iio_bridge_fast_primary_quality_decision"
        ),
        "board_iio_retry_fallback_quality_decision": board.get(
            "iio_bridge_retry_fallback_quality_decision"
        ),
        "host_iio_retry_fallback_quality_decision": host.get(
            "iio_bridge_retry_fallback_quality_decision"
        ),
        "board_iio_bridge_phy_adaptive_mcs_decision": board.get(
            "iio_bridge_phy_adaptive_mcs_decision"
        ),
        "host_iio_bridge_phy_adaptive_mcs_decision": host.get(
            "iio_bridge_phy_adaptive_mcs_decision"
        ),
        "board_iio_bridge_phy_adaptive_mcs_live_quality_bound": board.get(
            "iio_bridge_phy_adaptive_mcs_live_quality_bound"
        ),
        "host_iio_bridge_phy_adaptive_mcs_live_quality_bound": host.get(
            "iio_bridge_phy_adaptive_mcs_live_quality_bound"
        ),
        "board_iio_bridge_phy_adaptive_mcs_quality_source": board.get(
            "iio_bridge_phy_adaptive_mcs_quality_source"
        ),
        "host_iio_bridge_phy_adaptive_mcs_quality_source": host.get(
            "iio_bridge_phy_adaptive_mcs_quality_source"
        ),
        "board_iio_bridge_phy_adaptive_mcs_quality_updates": board.get(
            "iio_bridge_phy_adaptive_mcs_quality_updates"
        ),
        "host_iio_bridge_phy_adaptive_mcs_quality_updates": host.get(
            "iio_bridge_phy_adaptive_mcs_quality_updates"
        ),
        "board_iio_bridge_phy_adaptive_mcs_decision_polls": board.get(
            "iio_bridge_phy_adaptive_mcs_decision_polls"
        ),
        "host_iio_bridge_phy_adaptive_mcs_decision_polls": host.get(
            "iio_bridge_phy_adaptive_mcs_decision_polls"
        ),
        "board_iio_bridge_phy_adaptive_mcs_pre_burst_selection": board.get(
            "iio_bridge_phy_adaptive_mcs_pre_burst_selection"
        ),
        "host_iio_bridge_phy_adaptive_mcs_pre_burst_selection": host.get(
            "iio_bridge_phy_adaptive_mcs_pre_burst_selection"
        ),
        "board_iio_bridge_phy_adaptive_mcs_pre_burst_profile_source": board.get(
            "iio_bridge_phy_adaptive_mcs_pre_burst_profile_source"
        ),
        "host_iio_bridge_phy_adaptive_mcs_pre_burst_profile_source": host.get(
            "iio_bridge_phy_adaptive_mcs_pre_burst_profile_source"
        ),
        "board_iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source": board.get(
            "iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source"
        ),
        "host_iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source": host.get(
            "iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source"
        ),
        "board_iio_bridge_phy_native_modem_profile_application": board.get(
            "iio_bridge_phy_native_modem_profile_application"
        ),
        "host_iio_bridge_phy_native_modem_profile_application": host.get(
            "iio_bridge_phy_native_modem_profile_application"
        ),
        "board_iio_bridge_phy_python_modem_profile_mapping": board.get(
            "iio_bridge_phy_python_modem_profile_mapping"
        ),
        "host_iio_bridge_phy_python_modem_profile_mapping": host.get(
            "iio_bridge_phy_python_modem_profile_mapping"
        ),
        "board_iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound": board.get(
            "iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound"
        ),
        "host_iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound": host.get(
            "iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound"
        ),
        "board_iio_bridge_phy_adaptive_mcs_pre_burst_selection_polls": board.get(
            "iio_bridge_phy_adaptive_mcs_pre_burst_selection_polls"
        ),
        "host_iio_bridge_phy_adaptive_mcs_pre_burst_selection_polls": host.get(
            "iio_bridge_phy_adaptive_mcs_pre_burst_selection_polls"
        ),
        "board_iio_bridge_in_burst_priority_preemption_enabled": board.get(
            "iio_bridge_in_burst_priority_preemption_enabled"
        ),
        "host_iio_bridge_in_burst_priority_preemption_enabled": host.get(
            "iio_bridge_in_burst_priority_preemption_enabled"
        ),
        "board_iio_bridge_in_burst_priority_preemption_exercised": board.get(
            "iio_bridge_in_burst_priority_preemption_exercised"
        ),
        "host_iio_bridge_in_burst_priority_preemption_exercised": host.get(
            "iio_bridge_in_burst_priority_preemption_exercised"
        ),
        "board_iio_bridge_in_burst_priority_preemptions": board.get(
            "iio_bridge_in_burst_priority_preemptions"
        ),
        "host_iio_bridge_in_burst_priority_preemptions": host.get(
            "iio_bridge_in_burst_priority_preemptions"
        ),
        "board_iio_bridge_in_burst_priority_multiplexing_exercised": board.get(
            "iio_bridge_in_burst_priority_multiplexing_exercised"
        ),
        "host_iio_bridge_in_burst_priority_multiplexing_exercised": host.get(
            "iio_bridge_in_burst_priority_multiplexing_exercised"
        ),
        "board_iio_bridge_in_burst_priority_multiplexing_events": board.get(
            "iio_bridge_in_burst_priority_multiplexing_events"
        ),
        "host_iio_bridge_in_burst_priority_multiplexing_events": host.get(
            "iio_bridge_in_burst_priority_multiplexing_events"
        ),
        "board_iio_bridge_native_service_burst_leases": board.get(
            "iio_bridge_native_service_burst_leases"
        ),
        "host_iio_bridge_native_service_burst_leases": host.get(
            "iio_bridge_native_service_burst_leases"
        ),
        "board_iio_rf_sub_burst_exercised": board.get(
            "iio_bridge_rf_sub_burst_exercised"
        ),
        "host_iio_rf_sub_burst_exercised": host.get(
            "iio_bridge_rf_sub_burst_exercised"
        ),
        "board_iio_rf_sub_burst_bidirectional_service_exercised": board.get(
            "iio_bridge_rf_sub_burst_bidirectional_service_exercised"
        ),
        "host_iio_rf_sub_burst_bidirectional_service_exercised": host.get(
            "iio_bridge_rf_sub_burst_bidirectional_service_exercised"
        ),
        "board_iio_bridge_rf_lease_batch_high_water": board.get(
            "iio_bridge_rf_lease_batch_high_water"
        ),
        "host_iio_bridge_rf_lease_batch_high_water": host.get(
            "iio_bridge_rf_lease_batch_high_water"
        ),
        "board_iio_bridge_max_frames_per_rf_burst": board.get(
            "iio_bridge_max_frames_per_rf_burst"
        ),
        "host_iio_bridge_max_frames_per_rf_burst": host.get(
            "iio_bridge_max_frames_per_rf_burst"
        ),
        "board_iio_bridge_rf_sub_burst_deferred_frames": board.get(
            "iio_bridge_rf_sub_burst_deferred_frames"
        ),
        "host_iio_bridge_rf_sub_burst_deferred_frames": host.get(
            "iio_bridge_rf_sub_burst_deferred_frames"
        ),
        "board_iio_bridge_rf_sub_burst_preemption_points": board.get(
            "iio_bridge_rf_sub_burst_preemption_points"
        ),
        "host_iio_bridge_rf_sub_burst_preemption_points": host.get(
            "iio_bridge_rf_sub_burst_preemption_points"
        ),
        "board_iio_bridge_rf_sub_burst_reverse_service_events": board.get(
            "iio_bridge_rf_sub_burst_reverse_service_events"
        ),
        "host_iio_bridge_rf_sub_burst_reverse_service_events": host.get(
            "iio_bridge_rf_sub_burst_reverse_service_events"
        ),
        "board_iio_bridge_rf_sub_burst_same_direction_replays": board.get(
            "iio_bridge_rf_sub_burst_same_direction_replays"
        ),
        "host_iio_bridge_rf_sub_burst_same_direction_replays": host.get(
            "iio_bridge_rf_sub_burst_same_direction_replays"
        ),
        "board_iio_bridge_direction_fair_service_enabled": board.get(
            "iio_bridge_direction_fair_service_enabled"
        ),
        "host_iio_bridge_direction_fair_service_enabled": host.get(
            "iio_bridge_direction_fair_service_enabled"
        ),
        "board_iio_bridge_max_consecutive_direction_batches": board.get(
            "iio_bridge_max_consecutive_direction_batches"
        ),
        "host_iio_bridge_max_consecutive_direction_batches": host.get(
            "iio_bridge_max_consecutive_direction_batches"
        ),
        "board_iio_bridge_max_consecutive_direction_batches_seen": board.get(
            "iio_bridge_max_consecutive_direction_batches_seen"
        ),
        "host_iio_bridge_max_consecutive_direction_batches_seen": host.get(
            "iio_bridge_max_consecutive_direction_batches_seen"
        ),
        "board_iio_bridge_direction_fair_service_yields": board.get(
            "iio_bridge_direction_fair_service_yields"
        ),
        "host_iio_bridge_direction_fair_service_yields": host.get(
            "iio_bridge_direction_fair_service_yields"
        ),
        "board_iio_bridge_rf_burst_batch_size": board.get(
            "iio_bridge_rf_burst_batch_size"
        ),
        "host_iio_bridge_rf_burst_batch_size": host.get(
            "iio_bridge_rf_burst_batch_size"
        ),
        "board_iio_bridge_rf_burst_batch_high_water": board.get(
            "iio_bridge_rf_burst_batch_high_water"
        ),
        "host_iio_bridge_rf_burst_batch_high_water": host.get(
            "iio_bridge_rf_burst_batch_high_water"
        ),
        "board_iio_bridge_rf_burst_batch_high_water_by_direction": board.get(
            "iio_bridge_rf_burst_batch_high_water_by_direction"
        ),
        "host_iio_bridge_rf_burst_batch_high_water_by_direction": host.get(
            "iio_bridge_rf_burst_batch_high_water_by_direction"
        ),
        "board_iio_bridge_source_ack_pipeline_depth": board.get(
            "iio_bridge_source_ack_pipeline_depth"
        ),
        "host_iio_bridge_source_ack_pipeline_depth": host.get(
            "iio_bridge_source_ack_pipeline_depth"
        ),
        "board_iio_bridge_source_ack_pipeline_max_pending": board.get(
            "iio_bridge_source_ack_pipeline_max_pending"
        ),
        "host_iio_bridge_source_ack_pipeline_max_pending": host.get(
            "iio_bridge_source_ack_pipeline_max_pending"
        ),
        "board_iio_bridge_source_ack_latency_ms": board.get(
            "iio_bridge_source_ack_latency_ms"
        ),
        "host_iio_bridge_source_ack_latency_ms": host.get(
            "iio_bridge_source_ack_latency_ms"
        ),
        "board_iio_bridge_source_ack_max_latency_ms": board.get(
            "iio_bridge_source_ack_max_latency_ms"
        ),
        "host_iio_bridge_source_ack_max_latency_ms": host.get(
            "iio_bridge_source_ack_max_latency_ms"
        ),
        "board_iio_bridge_rf_burst_timing_ms": board.get("iio_bridge_rf_burst_timing_ms"),
        "host_iio_bridge_rf_burst_timing_ms": host.get("iio_bridge_rf_burst_timing_ms"),
        "board_iio_bridge_rf_burst_max_elapsed_ms": board.get(
            "iio_bridge_rf_burst_max_elapsed_ms"
        ),
        "host_iio_bridge_rf_burst_max_elapsed_ms": host.get(
            "iio_bridge_rf_burst_max_elapsed_ms"
        ),
        "board_iio_bridge_rf_burst_live_run_max_elapsed_ms": board.get(
            "iio_bridge_rf_burst_live_run_max_elapsed_ms"
        ),
        "host_iio_bridge_rf_burst_live_run_max_elapsed_ms": host.get(
            "iio_bridge_rf_burst_live_run_max_elapsed_ms"
        ),
        "board_iio_bridge_rf_burst_decode_max_elapsed_ms": board.get(
            "iio_bridge_rf_burst_decode_max_elapsed_ms"
        ),
        "host_iio_bridge_rf_burst_decode_max_elapsed_ms": host.get(
            "iio_bridge_rf_burst_decode_max_elapsed_ms"
        ),
        "board_tcp_final_exchange_ok": (
            board.get("tcp_final_exchange", {}).get("ok") is True
        ),
        "host_tcp_final_exchange_ok": (
            host.get("tcp_final_exchange", {}).get("ok") is True
        ),
        "board_tcp_final_exchange": board.get("tcp_final_exchange"),
        "host_tcp_final_exchange": host.get("tcp_final_exchange"),
        "board_tcp_final_exchange_grace_started": board.get(
            "tcp_final_exchange_grace_started"
        ),
        "host_tcp_final_exchange_grace_started": host.get(
            "tcp_final_exchange_grace_started"
        ),
        "board_tcp_queue_quiet_grace_started": board.get(
            "tcp_queue_quiet_grace_started"
        ),
        "host_tcp_queue_quiet_grace_started": host.get(
            "tcp_queue_quiet_grace_started"
        ),
        "board_tcp_queue_quiet_max_consecutive_s": board.get(
            "tcp_queue_quiet_max_consecutive_s"
        ),
        "host_tcp_queue_quiet_max_consecutive_s": host.get(
            "tcp_queue_quiet_max_consecutive_s"
        ),
        "board_tcp_control_drain": board.get("tcp_control_drain"),
        "host_tcp_control_drain": host.get("tcp_control_drain"),
        "board_tcp_control_drain_started": board.get("tcp_control_drain_started"),
        "host_tcp_control_drain_started": host.get("tcp_control_drain_started"),
        "board_tcp_control_drain_elapsed_s": board.get("tcp_control_drain_elapsed_s"),
        "host_tcp_control_drain_elapsed_s": host.get("tcp_control_drain_elapsed_s"),
        "board_tcp_control_drain_ok": board.get("tcp_control_drain_ok"),
        "host_tcp_control_drain_ok": host.get("tcp_control_drain_ok"),
        "board_to_board_report": str(board_path),
        "host_pc_report": str(host_path),
        "board_tcp_bits_per_second": board.get("tcp_bits_per_second"),
        "board_tcp_bytes": board.get("tcp_bytes"),
        "board_udp_bits_per_second": board.get("udp_bits_per_second"),
        "board_udp_bytes": board.get("udp_bytes"),
        "board_tcp_duration_s": board.get("tcp_duration_s"),
        "board_udp_duration_s": board.get("udp_duration_s"),
        "board_udp_jitter_ms": board.get("udp_jitter_ms"),
        "board_udp_lost_packets": board.get("udp_lost_packets"),
        "board_udp_packets": board.get("udp_packets"),
        "board_udp_lost_percent": board.get("udp_lost_percent"),
        "host_tcp_bits_per_second": host.get("host_tcp_bits_per_second"),
        "host_tcp_bytes": host.get("host_tcp_bytes"),
        "host_udp_bits_per_second": host.get("host_udp_bits_per_second"),
        "host_udp_bytes": host.get("host_udp_bytes"),
        "host_tcp_duration_s": host.get("host_tcp_duration_s"),
        "host_udp_duration_s": host.get("host_udp_duration_s"),
        "host_udp_jitter_ms": host.get("host_udp_jitter_ms"),
        "host_udp_lost_packets": host.get("host_udp_lost_packets"),
        "host_udp_packets": host.get("host_udp_packets"),
        "host_udp_lost_percent": host.get("host_udp_lost_percent"),
        "iperf_metric_quality_ready": not errors,
        "tcp_client_bytes": host.get("host_tcp_bytes"),
        "udp_client_bytes": host.get("host_udp_bytes"),
        "errors": errors,
    }
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        Path(args.output).write_text(encoded, encoding="utf-8")
    print(json.dumps(report, sort_keys=True))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
