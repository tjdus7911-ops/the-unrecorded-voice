# 효과음 목록 · 라이선스 (요구사항 16 산출물) — 자동 생성: `tools/audio/export_sfx_list.py`

- 모든 효과음은 `game/data/config/audio.json`의 ID로만 재생한다 (`Sounds` autoload). 파일 교체 시 코드 수정 없음.
- 외부(구매·다운로드) 음원은 **사용하지 않았다**. 전부 자체 합성(PH_) 또는 Supertonic 3 TTS 합성(TTS_)이며 `docs/production/asset_license_log.md`에 기록.
- 공포 효과음은 자막 여부와 관계없이 항상 실제 소리로 재생된다 (요구사항 15).

| ID | 파일 | 재생 | 사용 이벤트(JSON) | 사용 코드 | 라이선스 / 출처 | 상태 |
|---|---|---|---|---|---|---|
| amb_fluorescent_buzz | PH_amb_fluorescent_buzz.ogg | 루프 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| amb_fluorescent_hum | PH_amb_fluorescent_hum.ogg | 루프 | — | apt_corridor, lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| amb_pc_fan | PH_amb_pc_fan.ogg | 루프 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| amb_rain_heavy | PH_amb_rain_heavy.ogg | 루프 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| amb_rain_muffled | PH_amb_rain_muffled.ogg | 루프 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| amb_rain_window | PH_amb_rain_window.ogg | 루프 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| amb_tape_hiss | PH_amb_tape_hiss.ogg | 루프 | T01_frag3_recording | lvl_phase01, story_staging | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| amb_tape_motor | PH_amb_tape_motor.ogg | 루프 | — | lvl_phase01, prologue_story | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| amb_tape_rewind | PH_amb_tape_rewind.ogg | 루프 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| mon_breath | PH_mon_breath_0.wav, PH_mon_breath_1.wav, PH_mon_breath_2.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| mon_step | PH_mon_step_00.wav, PH_mon_step_01.wav, PH_mon_step_02.wav … | 1회 | — | — | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_cardboard_flap | PH_sfx_cardboard_flap_0.wav, PH_sfx_cardboard_flap_1.wav, PH_sfx_cardboard_flap_2.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_cassette_door | PH_sfx_cassette_door.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_cassette_insert | PH_sfx_cassette_insert.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_chair_creak | PH_sfx_chair_creak.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_child_laugh | TTS_child_laugh.wav | 1회 | EV08_soeun_corridor, T01_frag1_swing | story_staging | THIRD_PARTY 생성물 — Supertonic 3 (OpenRAIL-M, 상업 이용 가능) 음성 합성 + 자체 DSP | ⚠ 임시 (아이 웃음·놀이터 — 실제 녹음/라이선스 음원으로 교체 권장) |
| sfx_clock_tick | PH_sfx_clock_tick.wav, PH_sfx_clock_tock.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_deck_button | PH_sfx_deck_button.wav | 1회 | — | lvl_phase01, menu_item, prologue_story, ui_kit | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_door_bang | PH_sfx_door_bang_0.wav, PH_sfx_door_bang_1.wav, PH_sfx_door_bang_2.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_door_close | PH_sfx_door_close.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_door_creak_slow | PH_sfx_door_creak_slow.wav | 1회 | — | — | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_door_lock | PH_sfx_door_lock.wav | 1회 | — | lvl_phase01, prologue_story | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_door_locked | PH_sfx_door_locked.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_door_open | PH_sfx_door_open.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_door_unlock | PH_sfx_door_unlock.wav | 1회 | EV07_door_voice | — | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_drawer_close | PH_sfx_drawer_close.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_drawer_open | PH_sfx_drawer_open.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_elevator_ding | PH_sfx_elevator_ding.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_flashlight_off | PH_sfx_flashlight_off.wav | 1회 | — | flashlight | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_flashlight_on | PH_sfx_flashlight_on.wav | 1회 | — | flashlight | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_flicker_zap | PH_sfx_flicker_zap_0.wav, PH_sfx_flicker_zap_1.wav, PH_sfx_flicker_zap_2.wav | 1회 | EV06_blackout | lvl_phase01, story_staging | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_fluorescent_start | PH_sfx_fluorescent_start.wav | 1회 | EV10b_transition | — | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_handle_rattle | PH_sfx_handle_rattle.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_knock_3 | PH_sfx_knock_3.wav | 1회 | EV02_knock, EV07_door_voice | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_knock_soft | PH_sfx_knock_soft.wav | 1회 | — | — | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_light_switch | PH_sfx_light_switch.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_paper_rustle | PH_sfx_paper_rustle_0.wav, PH_sfx_paper_rustle_1.wav, PH_sfx_paper_rustle_2.wav | 1회 | — | inspect_system | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_pickup | PH_sfx_pickup.wav | 1회 | — | inspect_system, lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_power_down | PH_sfx_power_down.wav | 1회 | EV06_blackout, EV10b_transition | story_staging | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_swing_creak | PH_sfx_swing_creak.wav | 1회 | T01_frag1_swing | — | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_tape_rip | PH_sfx_tape_rip.wav | 1회 | — | lvl_phase01, story_staging | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_tape_stop | PH_sfx_tape_stop.wav | 1회 | — | lvl_phase01, prologue_story | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| sfx_thunder | PH_sfx_thunder_0.wav, PH_sfx_thunder_1.wav, PH_sfx_thunder_2.wav | 1회 | — | lvl_phase01 | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| step_concrete | PH_step_concrete_00.wav, PH_step_concrete_01.wav, PH_step_concrete_02.wav … | 1회 | — | story_staging | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| step_rug | PH_step_rug_00.wav, PH_step_rug_01.wav, PH_step_rug_02.wav … | 1회 | — | — | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| step_tile | PH_step_tile_00.wav, PH_step_tile_01.wav, PH_step_tile_02.wav … | 1회 | — | prologue_story | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| step_wood | PH_step_wood_00.wav, PH_step_wood_01.wav, PH_step_wood_02.wav … | 1회 | — | prologue_story | ORIGINAL — 자체 DSP 합성 (`tools/audio/make_placeholders.py`) | PLACEHOLDER (교체 예정) |
| tape_playground | TTS_tape_playground.wav | 1회 | EV04_first_recording | — | THIRD_PARTY 생성물 — Supertonic 3 (OpenRAIL-M, 상업 이용 가능) 음성 합성 + 자체 DSP | ⚠ 임시 (아이 웃음·놀이터 — 실제 녹음/라이선스 음원으로 교체 권장) |
