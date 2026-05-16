float distance_meters(const GuiPeer &a, const GuiPeer &b)
{
    if (!peer_has_position_model(a) || !peer_has_position_model(b)) {
        return -1.0f;
    }
    const float dx = static_cast<float>(a.x_cm - b.x_cm) / 100.0f;
    const float dy = static_cast<float>(a.y_cm - b.y_cm) / 100.0f;

    return std::sqrt(dx * dx + dy * dy);
}

float distance_from_local_meters(const GuiPeer &peer)
{
    if (!peer_has_position_model(peer)) {
        return -1.0f;
    }
    const float dx = static_cast<float>(peer.x_cm) / 100.0f;
    const float dy = static_cast<float>(peer.y_cm) / 100.0f;

    return std::sqrt(dx * dx + dy * dy);
}

ImVec2 topology_local_point(const GuiState *state, float center_x, float center_y)
{
    return ImVec2(center_x -
                      static_cast<float>(state->topology_center_x_cm) *
                          state->topology_zoom / 3.0f,
                  center_y +
                      static_cast<float>(state->topology_center_y_cm) *
                          state->topology_zoom / 3.0f);
}

ImVec2 clamp_topology_label(const ImVec2 &label_pos,
                            const ImVec2 &label_size,
                            const ImVec2 &origin,
                            const ImVec2 &canvas)
{
    return ImVec2(std::fmax(origin.x + 8.0f,
                            std::fmin(label_pos.x,
                                      origin.x + canvas.x - label_size.x - 14.0f)),
                  std::fmax(origin.y + 30.0f,
                            std::fmin(label_pos.y,
                                      origin.y + canvas.y - label_size.y - 10.0f)));
}

void draw_topology_badge(ImDrawList *draw,
                         const ImVec2 &label_pos,
                         const char *label,
                         ImU32 text_color,
                         ImU32 border_color)
{
    ImVec2 label_size = ImGui::CalcTextSize(label);
    ImVec2 badge_min(label_pos.x - 6.0f, label_pos.y - 4.0f);
    ImVec2 badge_max(label_pos.x + label_size.x + 6.0f,
                     label_pos.y + label_size.y + 4.0f);

    draw->AddRectFilled(badge_min, badge_max, IM_COL32(255, 255, 255, 242),
                        4.0f);
    draw->AddRect(badge_min, badge_max, border_color, 4.0f, 0, 1.0f);
    draw->AddText(label_pos, text_color, label);
}

float point_segment_distance(const ImVec2 &p, const ImVec2 &a, const ImVec2 &b)
{
    const float vx = b.x - a.x;
    const float vy = b.y - a.y;
    const float wx = p.x - a.x;
    const float wy = p.y - a.y;
    const float len2 = vx * vx + vy * vy;
    float t = len2 > 0.0f ? (wx * vx + wy * vy) / len2 : 0.0f;

    if (t < 0.0f) {
        t = 0.0f;
    } else if (t > 1.0f) {
        t = 1.0f;
    }
    const float px = a.x + t * vx;
    const float py = a.y + t * vy;
    const float dx = p.x - px;
    const float dy = p.y - py;
    return std::sqrt(dx * dx + dy * dy);
}

ImVec2 topology_peer_point(const GuiState *state,
                           const GuiPeer &peer,
                           std::size_t index,
                           float center_x,
                           float center_y)
{
    if (peer_has_position_model(peer)) {
        return ImVec2(center_x +
                          static_cast<float>(peer.x_cm - state->topology_center_x_cm) *
                              state->topology_zoom / 3.0f,
                      center_y -
                          static_cast<float>(peer.y_cm - state->topology_center_y_cm) *
                              state->topology_zoom / 3.0f);
    }
    const float angle = 0.75f + static_cast<float>(index) * 2.1f;
    const float radius = 74.0f * state->topology_zoom;

    return ImVec2(center_x + std::cos(angle) * radius,
                  center_y + std::sin(angle) * radius);
}

void center_topology_on_click(GuiState *state,
                              const ImVec2 &mouse,
                              float center_x,
                              float center_y)
{
    const float safe_zoom = state->topology_zoom > 0.1f ?
        state->topology_zoom : 1.0f;

    state->topology_center_x_cm +=
        static_cast<int>((mouse.x - center_x) * 3.0f / safe_zoom);
    state->topology_center_y_cm -=
        static_cast<int>((mouse.y - center_y) * 3.0f / safe_zoom);
    state->topology_zoom = 1.0f;
}

void render_topology_page(GuiState *state)
{
    begin_panel("Network Topology", ImVec2(0.0f, 0.0f));
    if (ImGui::Button("Zoom -")) {
        state->topology_zoom *= 0.8f;
        if (state->topology_zoom < 0.5f) {
            state->topology_zoom = 0.5f;
        }
    }
    ImGui::SameLine();
    ImGui::Text("%.1fx", static_cast<double>(state->topology_zoom));
    ImGui::SameLine();
    if (ImGui::Button("Zoom +")) {
        state->topology_zoom *= 1.25f;
        if (state->topology_zoom > 3.0f) {
            state->topology_zoom = 3.0f;
        }
    }
    ImGui::SameLine();
    if (ImGui::Button("Center")) {
        state->topology_zoom = 1.0f;
        state->topology_center_x_cm = 0;
        state->topology_center_y_cm = 0;
    }
    ImDrawList *draw = ImGui::GetWindowDrawList();
    ImVec2 origin = ImGui::GetCursorScreenPos();
    ImVec2 avail = ImGui::GetContentRegionAvail();
    ImVec2 canvas(avail.x > 320.0f ? avail.x : 320.0f,
                  avail.y > 388.0f ? avail.y - 68.0f : 320.0f);
    const float center_x = origin.x + canvas.x * 0.5f;
    const float center_y = origin.y + canvas.y * 0.5f;
    const ImVec2 local_point = topology_local_point(state, center_x, center_y);
    const ImVec2 mouse = ImGui::GetMousePos();
    int hovered_a = -1;
    int hovered_b = -1;
    int hovered_local = -1;
    float hovered_distance = 0.0f;

    draw->AddRectFilled(origin, ImVec2(origin.x + canvas.x, origin.y + canvas.y),
                        IM_COL32(247, 250, 252, 255));
    draw->AddRect(origin, ImVec2(origin.x + canvas.x, origin.y + canvas.y),
                  IM_COL32(190, 202, 212, 255));
    draw->AddText(ImVec2(origin.x + 14.0f, origin.y + 12.0f),
                  IM_COL32(30, 42, 54, 255),
                  "Relative co-location map, meters from GNSS/BDS, TOF, or TDOA");

    ImGui::InvisibleButton("topology-canvas-hitbox", canvas);
    if (ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
        center_topology_on_click(state, mouse, center_x, center_y);
    }

    std::vector<ImVec2> points;
    points.reserve(state->peers.size());
    for (std::size_t i = 0; i < state->peers.size(); ++i) {
        points.push_back(topology_peer_point(state,
                                             state->peers[i],
                                             i,
                                             center_x,
                                             center_y));
    }

    for (std::size_t i = 0; i < state->peers.size(); ++i) {
        const GuiPeer &peer = state->peers[i];
        char label[96];
        ImVec2 label_size;
        ImVec2 label_pos;
        float range_m = distance_from_local_meters(peer);

        draw->AddLine(local_point, points[i], IM_COL32(96, 125, 155, 145),
                      2.0f);
        if (range_m >= 0.0f) {
            std::snprintf(label, sizeof(label), "%.2f m", static_cast<double>(range_m));
        } else {
            std::snprintf(label, sizeof(label), "%s", "range pending");
        }
        label_size = ImGui::CalcTextSize(label);
        label_pos = clamp_topology_label(
            ImVec2((local_point.x + points[i].x) * 0.5f + 10.0f,
                   (local_point.y + points[i].y) * 0.5f - 22.0f),
            label_size, origin, canvas);
        draw_topology_badge(draw, label_pos, label,
                            range_m >= 0.0f ? IM_COL32(26, 91, 76, 255) :
                                               IM_COL32(93, 101, 109, 255),
                            range_m >= 0.0f ? IM_COL32(42, 132, 99, 255) :
                                               IM_COL32(150, 160, 170, 255));
    }

    for (std::size_t i = 0; i < state->peers.size(); ++i) {
        const GuiPeer &peer = state->peers[i];
        if (!state->selected_ap_eui.empty() &&
            peer.device_eui != state->selected_ap_eui) {
            for (std::size_t ap = 0; ap < state->peers.size(); ++ap) {
                if (state->peers[ap].device_eui == state->selected_ap_eui) {
                    draw->AddLine(points[i], points[ap],
                                  IM_COL32(102, 145, 214, 170), 2.0f);
                    draw->AddText(ImVec2((points[i].x + points[ap].x) * 0.5f + 6.0f,
                                          (points[i].y + points[ap].y) * 0.5f + 6.0f),
                                  IM_COL32(68, 92, 130, 255), "AP link");
                    break;
                }
            }
        }
    }

    for (std::size_t i = 0; i < state->peers.size(); ++i) {
        const float d = point_segment_distance(mouse, local_point, points[i]);
        if (d < 8.0f) {
            hovered_local = static_cast<int>(i);
            hovered_distance = distance_from_local_meters(state->peers[i]);
        }
    }
    for (std::size_t i = 0; i < state->peers.size(); ++i) {
        for (std::size_t j = i + 1u; j < state->peers.size(); ++j) {
            const float d = point_segment_distance(mouse, points[i], points[j]);
            if (d < 8.0f) {
                hovered_a = static_cast<int>(i);
                hovered_b = static_cast<int>(j);
                hovered_distance = distance_meters(state->peers[i], state->peers[j]);
            }
        }
    }
    if (hovered_local >= 0) {
        (void)hovered_distance;
        draw->AddLine(local_point,
                      points[static_cast<std::size_t>(hovered_local)],
                      IM_COL32(34, 132, 99, 255), 3.0f);
    }
    if (hovered_a >= 0 && hovered_b >= 0) {
        char label[96];
        ImVec2 label_size;
        if (hovered_distance >= 0.0f) {
            std::snprintf(label, sizeof(label), "%.2f m",
                          static_cast<double>(hovered_distance));
        } else {
            std::snprintf(label, sizeof(label), "%s", "range pending");
        }
        ImVec2 label_pos((points[static_cast<std::size_t>(hovered_a)].x +
                          points[static_cast<std::size_t>(hovered_b)].x) * 0.5f + 8.0f,
                         (points[static_cast<std::size_t>(hovered_a)].y +
                          points[static_cast<std::size_t>(hovered_b)].y) * 0.5f - 18.0f);
        label_size = ImGui::CalcTextSize(label);
        label_pos = clamp_topology_label(label_pos, label_size, origin, canvas);
        draw->AddLine(points[static_cast<std::size_t>(hovered_a)],
                      points[static_cast<std::size_t>(hovered_b)],
                      IM_COL32(34, 132, 99, 255), 3.0f);
        draw_topology_badge(draw, label_pos, label,
                            IM_COL32(20, 96, 72, 255),
                            IM_COL32(34, 132, 99, 255));
    }

    draw->AddCircleFilled(local_point, 10.0f, IM_COL32(46, 125, 50, 255));
    draw->AddCircle(local_point, 17.0f, IM_COL32(46, 125, 50, 120), 24, 2.0f);
    {
        const GuiBoard *board = selected_board(*state);
        const char *local_label = board && !board->device_eui.empty() ?
            board->device_eui.c_str() : "Local board";
        ImVec2 label_size = ImGui::CalcTextSize(local_label);
        ImVec2 label_pos = clamp_topology_label(
            ImVec2(local_point.x + 14.0f, local_point.y - 14.0f),
            label_size, origin, canvas);

        draw_topology_badge(draw, label_pos, local_label,
                            IM_COL32(25, 78, 36, 255),
                            IM_COL32(46, 125, 50, 255));
    }

    for (std::size_t i = 0; i < state->peers.size(); ++i) {
        const GuiPeer &peer = state->peers[i];
        const bool is_local = peer.device_eui == state->selected_board_eui;
        const bool is_ap = peer.device_eui == state->selected_ap_eui;
        const bool has_gnss = peer_has_gnss_position(peer);
        const bool has_timing = peer_has_timing_position(peer);
        const ImU32 color = is_local ? IM_COL32(46, 125, 50, 255) :
                            is_ap ? IM_COL32(203, 111, 33, 255) :
                                    IM_COL32(31, 91, 164, 255);
        draw->AddCircleFilled(points[i], is_ap ? 10.0f : 8.0f, color);
        if (has_gnss) {
            const float pulse = 13.0f +
                static_cast<float>(std::sin(ImGui::GetTime() * 4.0)) * 2.0f;
            draw->AddCircle(points[i], pulse, IM_COL32(16, 150, 128, 210), 32, 2.0f);
            draw->AddCircle(points[i], pulse + 5.0f, IM_COL32(16, 150, 128, 80), 32, 1.5f);
            draw->AddText(ImVec2(points[i].x - 18.0f, points[i].y + 16.0f),
                          IM_COL32(8, 98, 84, 255), "GNSS");
        } else if (has_timing) {
            draw->AddCircle(points[i], 14.0f, IM_COL32(82, 104, 190, 190), 24, 2.0f);
            draw->AddText(ImVec2(points[i].x - 14.0f, points[i].y + 16.0f),
                          IM_COL32(66, 78, 160, 255), "TOF");
        }
        draw->AddCircle(points[i], static_cast<float>(peer.error_radius_cm) / 12.0f,
                        IM_COL32(77, 121, 168, 90), 24, 1.0f);
        ImVec2 text_pos(points[i].x + 12.0f, points[i].y - 12.0f);
        text_pos.x = std::fmax(origin.x + 8.0f,
                               std::fmin(text_pos.x, origin.x + canvas.x - 180.0f));
        text_pos.y = std::fmax(origin.y + 30.0f,
                               std::fmin(text_pos.y, origin.y + canvas.y - 18.0f));
        draw->AddText(text_pos,
                      IM_COL32(24, 33, 41, 255), peer.device_eui.c_str());
    }
    ImGui::Text("AP: %s", state->selected_ap_eui.c_str());
    ImGui::SameLine();
    ImGui::Text("Range: GNSS/BDS, time-synced TOF, packet TDOA, or test fixture only.");
    ImGui::Text("Double click the map to restore 1.0x and center on that point.");
    ImGui::Text("Topology updates: %u  source: %s",
                state->topology_update_count,
                state->topology_metrics_live ? "live daemon metrics" :
                                               "position source pending/test fixture");
    ImGui::TextUnformatted("Local-to-peer range labels are always shown; hover a link for detail.");
    end_panel();
}
