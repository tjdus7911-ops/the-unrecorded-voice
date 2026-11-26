# Git LFS 업로드 오류 — 정확한 메시지와 해결 방법

## 발생 상황
- 일시: 2026-11-26, Claude 클라우드 작업 세션에서 `git push origin main`
- 일반 Git 객체(코드·문서) 푸시는 **정상**. LFS 객체(PNG/WAV 등) 업로드 단계에서만 실패.
- 같은 명령을 `git lfs push origin main`으로 1회 재시도 → 동일 오류. 그 이상 우회 시도하지 않음.

## 정확한 오류 메시지
```
LFS: Authorization error: https://github-cloud.s3.amazonaws.com/alambic/media/1322253492/80/97/809747a5808ce64274f2a2b26e6f2edbe70d589a2a44f8248468a28a156a7a44?actor_id=314188652&key_id=0&repo_id=1472578563
Check that you have proper access to the repository
...
error: failed to push some refs to 'https://github.com/tjdus7911-ops/the-unrecorded-voice'
```

## 원인 (판단)
1. Git LFS는 두 단계로 업로드한다: ① GitHub LFS API(`/info/lfs/objects/batch`)에서 업로드 허가를 받고 ② 그 응답에 담긴 **GitHub의 저장소(S3) 주소**로 파일을 직접 올린다.
2. ①은 통과했지만 ②의 S3 주소(`github-cloud.s3.amazonaws.com`) 요청이 권한 오류로 거부되었다.
3. Claude 세션은 GitHub 접근을 세션 전용 연동(프록시·토큰)으로 하는데, 이 경로가 **LFS 저장소 업로드까지는 허용하지 않는 것으로 보인다**. 저장소 권한이나 사용자 계정 문제가 아니다.

## 해결 방법

### A. 사용자 PC에서 푸시 (권장 · 가장 확실)
1. 이 작업 공간 보관본 ZIP(`the-unrecorded-voice_project_*.zip`)을 내려받아 압축을 푼다.
2. PowerShell에서:
   ```powershell
   cd the-unrecorded-voice
   git lfs install
   git remote -v                         # origin 이 github.com/tjdus7911-ops/the-unrecorded-voice 인지 확인
   .\tools\windows\enable_lfs_assets.ps1 # .gitignore의 '임시 제외' 블록을 지우고 바이너리를 LFS로 추가
   git commit -m "assets: add binary assets via Git LFS"
   git push origin main
   ```
3. 처음 푸시할 때 GitHub 로그인 창이 뜨면 본인 계정으로 로그인한다 (Git Credential Manager).

### B. GitHub LFS 용량 확인
GitHub 무료 계정은 LFS 저장 용량·대역폭 한도가 있다. 저장소 Settings → Billing 에서 사용량을 확인한다.
현재 바이너리 총량은 약 150~200 MB(텍스처·모델·음원·.blend)로 무료 한도 안에서 시작 가능하다.

### C. Claude 세션 쪽 권한
Claude 세션에서 LFS를 다시 시도하려면 Claude의 GitHub 연동 권한이 LFS 업로드를 허용해야 한다.
해결 전까지 Claude는 **바이너리를 커밋하지 않고**, 모든 바이너리를 저장소의 스크립트로 재생성(`tools/build_all.sh`)할 수 있게 유지한다.

## 현재 운영 방식
- 텍스트(코드·문서·데이터·빌드 스크립트) → GitHub
- 바이너리(.blend, .gltf/.bin, 텍스처, 음원, 렌더) → 채팅으로 전달하는 ZIP 보관본 + 재생성 스크립트
