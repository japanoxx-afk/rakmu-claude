# RhakMu 멀티플레이 안정 실행 순서

현재 안정 테스트 프로필 기준입니다.

- 서버 PC: `26.157.67.215`
- 원격 PC: `26.240.153.112`
- 네트워크: Radmin VPN `26.x`
- 더미서버 프로필: 방장 identity + 클라이언트 직접 시작 경로

## 이 프로필을 쓰는 이유

2026-06-06 22:46 로그에서는 더미서버가 시작 패킷을 끼워 넣지 않았습니다.

```text
Game start sync mode=none ... payload=02 00 00
Game start relay suppressed ...
```

그런데도 게스트가 약 13초 뒤 방에서 나갔습니다. 남은 차이는 방 입장 응답의
identity였습니다.

- 실패 로그: 입장 응답 identity가 입장자 계정이었음
- 정상 이력 `34e85ea`: 입장 응답 identity가 방장 계정이었음

그래서 안정 프로필은 아래 값으로 고정합니다.

```text
RoomJoinIdentityMode: host
GameStartSyncMode: none
ChannelUserListReplyMode: members
```

## 1. 양쪽 PC에서 게임 실행 전 패치

관리자 권한 PowerShell을 열고 실행합니다.

서버 PC:

```powershell
cd C:\Users\seo\Documents\라크무
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-RhakMuClientPatches.ps1
```

원격 PC:

```powershell
cd C:\Users\seo\Documents\rakmu-git
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-RhakMuClientPatches.ps1
```

마지막 줄이 아래처럼 나와야 합니다.

```text
RhakMu patch bundle version: 2026-06-06.2305
```

## 2. 양쪽 PC에서 캡처 시작

서버 PC:

```powershell
cd C:\Users\seo\Documents\라크무
powershell -NoProfile -ExecutionPolicy Bypass -File .\Start-RhakMuUdpCapture.ps1
```

원격 PC:

```powershell
cd C:\Users\seo\Documents\rakmu-git
powershell -NoProfile -ExecutionPolicy Bypass -File .\Start-RhakMuUdpCapture.ps1
```

## 3. 서버 PC에서만 더미서버 시작

서버 PC:

```powershell
cd C:\Users\seo\Documents\라크무
powershell -NoProfile -ExecutionPolicy Bypass -File .\Start-RhakMuStableServer.ps1
```

시작 로그에 아래 3줄이 보여야 합니다.

```text
RoomJoinIdentityMode: host
GameStartSyncMode: none
ChannelUserListReplyMode: members
```

## 4. 양쪽 PC에서 RhakMu 실행 및 테스트

1. 서로 다른 계정으로 로그인합니다. 예: `test1`, `test2`
2. 1차 테스트: 원격 PC가 방 생성 -> 서버 PC 입장 -> 원격 PC가 Start
3. 2차 테스트: 서버 PC가 방 생성 -> 원격 PC 입장 -> 서버 PC가 Start

Start 버튼을 누를 때 더미서버에는 아래처럼 나와야 정상입니다.

```text
Game start sync mode=none ...
Game start relay suppressed ...
```

정상 테스트 중에는 아래 로그가 나오면 안 됩니다.

```text
TCP-ROOM-BROADCAST ... type=0x0FFF
```

이 줄이 보이면 더미서버가 잘못된 프로필로 실행된 것입니다.

## 5. 테스트 후 양쪽 PC에서 캡처 종료

양쪽 PC에서 실행합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Stop-RhakMuUdpCapture.ps1
```

## 그래도 동시에 시작하지 않으면 확인할 것

다음 정보를 로그와 함께 알려주세요.

- 어느 PC가 방을 만들었는지
- 방장 계정명
- 입장 계정명
- 더미서버 시작 로그에 `RoomJoinIdentityMode: host`가 있었는지
- 방 입장 로그가 `Room join reply identity mode=host`였는지
- Start 후 약 13초 뒤 `0x11FF`가 찍혔는지
