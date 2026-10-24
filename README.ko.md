# 술술 (Sulsul)

[English](README.md) | 한국어

> 영어 [README.md](README.md)가 기준 문서이고, 이 문서는 그 번역입니다. 내용이 다르면 영어 문서를 따릅니다.

술술은 Prakash Joshi(Pax)의 [VoiceInk](https://github.com/Beingpax/VoiceInk)를 수정한 포크이며, GNU General Public License v3.0으로 배포됩니다. 원래의 저작권 고지는 소스에 그대로 남아 있습니다. 이 포크는 VoiceInk 이름에 대한 어떤 상표권도 부여하지 않습니다.

Upstream: https://github.com/Beingpax/VoiceInk

이 저장소는 소수의 사람이 쓰는 개인 빌드입니다. 각자 자신의 API 키를 직접 입력하며, API 키는 앱에 포함되어 있지 않습니다. 변경 목록은 [NOTICE](NOTICE), 빌드 방법은 [BUILDING.md](BUILDING.md)를 보세요.

이 포크의 변경점:

- 앱 이름은 술술(제품명 Sulsul, 번들 ID `com.qaws81877.sulsul`)이고, 설치된 VoiceInk와 데이터를 공유하지 않도록 자체 Application Support 폴더, Keychain 서비스, 환경설정을 따로 씁니다.
- 라이선스, 체험판, 구매 시스템(Polar 포함)을 없앴습니다. 릴리스 빌드는 모든 기능이 열려 있습니다.
- 앱이 원작자의 서버(공지, Sparkle appcast, GitHub 별점 안내, Polar, 앱 안의 문서 링크)에 더 이상 접속하지 않습니다.
- VoiceInk Refine과 그 XPC 서비스를 제거했습니다. 해당 모델의 라이선스가 재배포를 허용하지 않기 때문입니다.
- iCloud 단어장 동기화는 꺼져 있습니다. 원래의 iCloud 컨테이너에 의존하던 기능입니다.
- 온보딩에서 전사 모델 다운로드를 건너뛰거나 Whisper 모델을 고를 수 있습니다. Parakeet이 필수가 아닙니다.

Xcode 스킴 이름은 여전히 `VoiceInk`입니다. Apple Developer Team ID는 git에서 제외된 `Signing.local.xcconfig`에만 넣고([Signing.xcconfig](Signing.xcconfig) 참고), 절대 커밋하지 마세요.

## 설치

[Homebrew](https://brew.sh)로 설치합니다.

```bash
brew install --cask qaws81877/sulsul/sulsul
```

또는 [최신 릴리스](https://github.com/qaws81877/sulsul/releases/latest)에서 `Sulsul.dmg`를 받아 술술을 응용 프로그램 폴더로 끌어다 놓으세요. 앱은 서명과 공증이 되어 있고, macOS 15.0 이상이 필요합니다.

술술은 스스로 업데이트합니다. 술술 메뉴의 "업데이트 확인…"을 선택하세요. Homebrew cask는 비공식 tap [qaws81877/homebrew-sulsul](https://github.com/qaws81877/homebrew-sulsul)에 있습니다.

## 기능

- 로컬 및 클라우드 전사
- 맨 앞에 있는 앱이나 음성 트리거에 따라 바뀌는 모드
- 직접 입력한 제공자 키로 쓰는 선택형 AI 다듬기
- 전역 키보드·마우스 단축키
- 개인 단어장과 텍스트 치환

## 요구 사항

- macOS 15.0 이상

## 개인정보

술술에는 분석, 텔레메트리, 계정, 자체 서버가 없고, 개발자는 사용자의 데이터를 전혀 받지 않습니다. 일부 기능은 **사용자가 직접 고른** 서비스로, 사용자 본인의 API 키를 써서 데이터를 보냅니다.

- **클라우드 전사:** 녹음한 오디오가 선택한 모델의 제공자로 전송됩니다.
- **AI 다듬기:** 받아쓴 텍스트와 단어장의 단어가 선택한 LLM 제공자로 전송됩니다. 대부분의 프롬프트는 현재 모드의 선택형 맥락 정보(선택한 텍스트는 새 모드에서 기본 켜짐, 클립보드와 현재 창에서 읽은 텍스트는 기본 꺼짐)도 함께 보냅니다.
- **한국어 정리**(기본 제공 한국어 프롬프트이며 OpenAI, Anthropic 또는 제공자 미선택일 때 쓰입니다)는 받아쓴 텍스트와 단어장의 단어를 먼저 OpenAI로 보내고, OpenAI가 실패했는데 Anthropic 키를 넣어 두었다면 Anthropic에도 보냅니다. OpenAI 키가 없거나 Anthropic을 골랐다면 Anthropic에만 보냅니다. 선택한 텍스트, 클립보드, 화면 맥락은 보내지 않습니다. OpenAI나 Anthropic API 키를 넣으면, 손대지 않은 기본 받아쓰기 모드에서 이 정리가 한 번 자동으로 켜집니다.

이 제공자들은 각자의 약관에 따라 데이터를 처리하므로, 민감한 내용을 보내기 전에 약관을 확인하세요. 로컬 모델을 쓰거나, AI 다듬기를 끄거나, 본인 맥의 Ollama를 쓰면 모든 데이터가 이 맥 안에만 머뭅니다. 녹음, 기록, 단어장은 이 맥에 저장되고 API 키는 macOS Keychain에 저장됩니다. 업데이트 확인은 GitHub에, 선택한 모델 다운로드는 Hugging Face에 접속합니다.

## 라이선스

GNU General Public License v3.0입니다. 전문은 [LICENSE](LICENSE)에 있습니다.

## 감사의 말

사용한 오픈소스와 모델의 목록, 저작권 고지, 라이선스 전문은 영어 [README.md의 Acknowledgments](README.md#acknowledgments)와 [VoiceInk/Resources/THIRD_PARTY_NOTICES.txt](VoiceInk/Resources/THIRD_PARTY_NOTICES.txt)에 있습니다. 같은 파일이 앱 안에도 들어 있습니다.

VoiceInk는 Pax가 만들었습니다.
