import Foundation
import PasteFlowCore

/// 패널·미리보기·핀이 함께 쓰는 동작. `AppDelegate`가 시작할 때 연결한다.
enum AppActions {
    /// 패널 항목 복사(윈도우판 `_on_copy_item`) — 클립보드 + 큐 + 히스토리 맨 위 + 복사 알림.
    static var copyItem: ((ClipItem) -> Void)?
    /// 이미지를 파일로 저장하고 경로 글자를 클립보드에.
    static var copyPath: ((ClipItem) -> Void)?
    /// 이미지 PNG를 OCR(영역 OCR과 같은 게이트웨이 경로).
    static var ocr: ((Data) -> Void)?
    /// 패널 항목 글자 수정 창.
    static var editText: ((Int64) -> Void)?
}
