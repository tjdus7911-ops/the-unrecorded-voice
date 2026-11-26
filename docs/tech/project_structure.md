# 프로젝트 폴더 구조

```
the-unrecorded-voice/
├─ CLAUDE.md                  # AI 개발 세션용 프로젝트 규칙 (항상 먼저 읽음)
├─ README.md
├─ .gitattributes             # Git LFS 대상 정의
├─ .gitignore
│
├─ docs/
│  ├─ README.md               # 문서 색인
│  ├─ requirements/           # 사용자 원문 요구사항 (수정 금지, 추가만)
│  ├─ design/                 # 기획 해석·결정 문서 (사운드 바이블, 미확정 항목 등)
│  ├─ tech/                   # 엔진 선정, 환경 구성, 에셋 파이프라인
│  └─ production/             # 개발 로그, 라이선스 기록, 리뷰 기록
│
├─ art/                       # 원본(DCC) 에셋 — 게임에 직접 로드되지 않음
│  ├─ blender/
│  │  ├─ environments/
│  │  │  ├─ studio/            # 현대 음성 복원 작업실
│  │  │  ├─ studio_corridor/   # 작업실 외부 상가 복도
│  │  │  └─ apartment_1998/    # 1998년 복도식 아파트 (단일 마스터 구조)
│  │  ├─ props/               # 녹음기·테이프·손전등 등 개별 오브젝트
│  │  ├─ characters/          # 캐릭터 원본 (REF 11~20)
│  │  ├─ animations/          # 액션 라이브러리
│  │  └─ _library/            # 공용 재질·모듈 건축 키트
│  ├─ textures_source/        # 텍스처 원본(고해상도·레이어)
│  ├─ concept/                # 컨셉 시트
│  └─ renders/                # 검토용 렌더 (공간별 하위 폴더)
│
├─ tools/
│  ├─ blender/                # Blender Python 빌드·익스포트 스크립트
│  ├─ audio/                  # 임시 음원 생성, 음원 처리 스크립트
│  └─ ci/                     # 자동 테스트 실행 스크립트
│
├─ game/                      # Godot 4.7 프로젝트 루트 (project.godot)
│  ├─ assets/
│  │  ├─ models/{environments,props,characters}/   # Blender에서 내보낸 GLB
│  │  ├─ textures/  materials/
│  │  └─ audio/
│  │     ├─ voice/<character_id>/   # 대사 음성
│  │     ├─ breathing/  heartbeat/  # 동적 호흡·심장 박동
│  │     ├─ ghosts/<ghost_id>/      # 귀신 고유 사운드
│  │     ├─ sfx/  ambience/  music/
│  ├─ data/
│  │  ├─ dialogue/            # 대사 데이터 (JSON) — 음성 파일은 경로로만 참조
│  │  ├─ story/               # 챕터·씬·플래그 정의
│  │  └─ config/              # 캐릭터·음성 ID, 조명 상태 등
│  ├─ scenes/{levels,player,props,ui,tests}/
│  └─ scripts/{player,systems,audio,interaction,ui,data}/
│
├─ refs_local/                # (git 제외) 출처 미확인 레퍼런스 이미지 로컬 보관
└─ builds/                    # (git 제외) 익스포트 빌드
```

## 원칙

- **원본과 게임용 분리**: `.blend`는 `art/`, 게임이 로드하는 GLB는 `game/assets/`. GLB는 스크립트(`tools/blender/export_*.py`)로만 재생성한다.
- **임시 리소스 구분**: 임시 음원·텍스처는 파일명 앞에 `PH_`(placeholder)를 붙이고 `docs/production/asset_license_log.md`에 `PLACEHOLDER`로 기록. 최종 에셋으로 교체 시 같은 ID로 덮어쓴다.
- **데이터와 코드 분리**: 대사·음성·조명 상태·챕터 조건은 `game/data/`의 JSON으로 관리하고 코드는 ID로만 참조한다 (다국어·음성 교체 시 코드 변경 없음).
- **명명 규칙**: `snake_case`, 영문. 공간 접두사 `stu_`(작업실), `cor_`(상가 복도), `apt_`(1998 아파트), 오브젝트 `prop_`, 캐릭터 `chr_`, 귀신 `gst_`.
