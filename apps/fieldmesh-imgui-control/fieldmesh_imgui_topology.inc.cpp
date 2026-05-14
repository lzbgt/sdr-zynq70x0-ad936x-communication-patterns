float distance_meters(const GuiPeer &a, const GuiPeer &b)
{
    const float dx = static_cast<float>(a.x_cm - b.x_cm) / 100.0f;
    const float dy = static_cast<float>(a.y_cm - b.y_cm) / 100.0f;

    return std::sqrt(dx * dx + dy * dy);
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

void render_topology_page(GuiState *state)
{
    begin_panel("Network Topology", ImVec2(0.0f, 0.0f));
    ImGui::SliderFloat("Zoom", &state->topology_zoom, 0.5f, 3.0f, "%.1fx");
    ImGui::SameLine();
    if (ImGui::Button("Reset View")) {
        state->topology_zoom = 1.0f;
    }
    ImDrawList *draw = ImGui::GetWindowDrawList();
    ImVec2 origin = ImGui::GetCursorScreenPos();
    ImVec2 avail = ImGui::GetContentRegionAvail();
    ImVec2 canvas(avail.x > 320.0f ? avail.x : 320.0f,
                  avail.y > 320.0f ? avail.y - 68.0f : 320.0f);
    const float center_x = origin.x + canvas.x * 0.5f;
    const float center_y = origin.y + canvas.y * 0.5f;
    const ImVec2 mouse = ImGui::GetMousePos();
    int hovered_a = -1;
    int hovered_b = -1;
    float hovered_distance = 0.0f;

    draw->AddRectFilled(origin, ImVec2(origin.x + canvas.x, origin.y + canvas.y),
                        IM_COL32(247, 250, 252, 255));
    draw->AddRect(origin, ImVec2(origin.x + canvas.x, origin.y + canvas.y),
                  IM_COL32(190, 202, 212, 255));
    draw->AddText(ImVec2(origin.x + 14.0f, origin.y + 12.0f),
                  IM_COL32(30, 42, 54, 255),
                  "Relative co-location map, meters from packet timing/GNSS fusion");

    std::vector<ImVec2> points;
    points.reserve(state->peers.size());
    for (const GuiPeer &peer : state->peers) {
        points.push_back(ImVec2(center_x + static_cast<float>(peer.x_cm) *
                                           state->topology_zoom / 3.0f,
                                center_y - static_cast<float>(peer.y_cm) *
                                           state->topology_zoom / 3.0f));
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
        for (std::size_t j = i + 1u; j < state->peers.size(); ++j) {
            const float d = point_segment_distance(mouse, points[i], points[j]);
            if (d < 8.0f) {
                hovered_a = static_cast<int>(i);
                hovered_b = static_cast<int>(j);
                hovered_distance = distance_meters(state->peers[i], state->peers[j]);
            }
        }
    }
    if (hovered_a >= 0 && hovered_b >= 0) {
        char label[96];
        std::snprintf(label, sizeof(label), "%.2f m",
                      static_cast<double>(hovered_distance));
        ImVec2 label_pos((points[static_cast<std::size_t>(hovered_a)].x +
                          points[static_cast<std::size_t>(hovered_b)].x) * 0.5f + 8.0f,
                         (points[static_cast<std::size_t>(hovered_a)].y +
                          points[static_cast<std::size_t>(hovered_b)].y) * 0.5f - 18.0f);
        label_pos.x = std::fmax(origin.x + 8.0f,
                                std::fmin(label_pos.x, origin.x + canvas.x - 80.0f));
        label_pos.y = std::fmax(origin.y + 30.0f,
                                std::fmin(label_pos.y, origin.y + canvas.y - 22.0f));
        draw->AddLine(points[static_cast<std::size_t>(hovered_a)],
                      points[static_cast<std::size_t>(hovered_b)],
                      IM_COL32(34, 132, 99, 255), 3.0f);
        ImVec2 label_size = ImGui::CalcTextSize(label);
        ImVec2 badge_min(label_pos.x - 6.0f, label_pos.y - 4.0f);
        ImVec2 badge_max(label_pos.x + label_size.x + 6.0f,
                         label_pos.y + label_size.y + 4.0f);
        draw->AddRectFilled(badge_min, badge_max, IM_COL32(255, 255, 255, 238),
                            4.0f);
        draw->AddRect(badge_min, badge_max, IM_COL32(34, 132, 99, 255), 4.0f,
                      0, 1.0f);
        draw->AddText(label_pos, IM_COL32(20, 96, 72, 255), label);
    }

    for (std::size_t i = 0; i < state->peers.size(); ++i) {
        const GuiPeer &peer = state->peers[i];
        const bool is_local = peer.device_eui == state->selected_board_eui;
        const bool is_ap = peer.device_eui == state->selected_ap_eui;
        const ImU32 color = is_local ? IM_COL32(46, 125, 50, 255) :
                            is_ap ? IM_COL32(203, 111, 33, 255) :
                                    IM_COL32(31, 91, 164, 255);
        draw->AddCircleFilled(points[i], is_ap ? 10.0f : 8.0f, color);
        draw->AddCircle(points[i], static_cast<float>(peer.error_radius_cm) / 12.0f,
                        IM_COL32(77, 121, 168, 90), 24, 1.0f);
        ImVec2 text_pos(points[i].x + 12.0f, points[i].y - 12.0f);
        text_pos.x = std::fmax(origin.x + 8.0f,
                               std::fmin(text_pos.x, origin.x + canvas.x - 180.0f));
        text_pos.y = std::fmax(origin.y + 30.0f,
                               std::fmin(text_pos.y, origin.y + canvas.y - 18.0f));
        draw->AddText(text_pos,
                      IM_COL32(24, 33, 41, 255), peer.hostname.c_str());
    }
    ImGui::Dummy(canvas);
    ImGui::Text("AP: %s", state->selected_ap_eui.c_str());
    ImGui::SameLine();
    ImGui::Text("Hover between peers for distance; AP membership links are always shown.");
    end_panel();
}
