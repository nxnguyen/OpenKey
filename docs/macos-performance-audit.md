# Đánh giá RAM/CPU của OpenKey trên macOS

Phạm vi: kiểm tra bản fork tại commit `9201ee9`, đo thử độc lập với bàn
phím thật. Đây là đánh giá và đề xuất; các tối ưu dưới đây chưa được áp
dụng vào bản 2.0.6 đã cài.

## Đã thay bản ứng dụng

Đã thay `/Applications/OpenKey.app` bằng 2.0.6/build 50, xác minh chữ ký
và checksum executable khớp bản build. Sao lưu bundle và preferences
cũ trong thư mục backup riêng bên ngoài repository. Dừng bản cũ và
login helper cũ trước khi thay.

Bản mới khởi chạy nhưng đang ở hộp thoại cấp quyền Accessibility.
Stack sample xác nhận `AppDelegate askPermission` → `NSAlert runModal`;
`CGGetEventTapList` chưa có tap của PID mới. Người dùng chọn cấp quyền
sau, nên chưa kiểm tra được gõ tiếng Việt thật sau khi cài.

## Số đo

Trong trạng thái chờ cấp quyền: CPU tức thời 0.0%, physical footprint
25.9 MiB, peak 26.7 MiB. Không coi đây là số đo lúc đang gõ. RSS có thể
giảm do nén/swap, không dùng RSS để so sánh trực tiếp với bản cũ đã chạy
nhiều giờ. Kích thước bundle mới trên đĩa khoảng 1.3 MiB.

Probe liên kết object Release thật, fake ranh giới tạo tap và gửi phím để
không gõ vào ứng dụng người dùng. Gọi WindowServer vẫn là API thật;
input source khác tiếng Anh, macro, kiểm tra chính tả và smart switch
được tắt để cô lập phép đo. Một lượt đo, không phải benchmark dài hạn:

| Trường hợp | Phím | Lấy danh sách cửa sổ | Wall time | CPU time |
|---|---:|---:|---:|---:|
| 500 chuỗi `as `, workaround autocomplete tắt | 1.500 | 500 | 107.92 ms | 25.20 ms |
| 500 chuỗi `as `, workaround autocomplete bật | 1.500 | 1.000 | 171.81 ms | 46.05 ms |
| Chỉ engine C++, 100.000 chuỗi `as ` | 300.000 | 0 | 10.87 ms | 10.85 ms |

Hai dòng đầu là hai cấu hình khác nhau, không phải kết quả trước/sau
một bản tối ưu. Việc tắt workaround làm thay đổi hành vi nên không
đề xuất tự tắt cấu hình hiện tại chỉ để giảm số đo.

## Các điểm cần ưu tiên

1. **Giảm công việc trong callback.** `isSpotlightVisible()` gọi
   `CGWindowListCopyWindowInfo` để lấy thông tin toàn bộ cửa sổ. Hai hàm
   `shouldUseRecommendWorkaround` và `shouldUseSelectionReplacement`
   có thể gọi nó hai lần cho cùng một phím. Nên dùng một snapshot trong
   cùng callback, đánh giá điều kiện rẻ trước khi hỏi WindowServer.
   Nếu cache qua nhiều callback, phải kiểm tra kỹ lúc mở/đóng Spotlight
   để không làm sai cách thay chữ. Apple cũng mô tả tạo dictionary cửa
   sổ là thao tác tương đối tốn chi phí.
2. **Sửa ownership input source.** Nhánh `vOtherLanguage` đọc input
   source trên cả key down và key up. Trường hợp ngôn ngữ khác `en`
   trả về trước `CFRelease(isource)`; trường hợp mảng ngôn ngữ rỗng
   cũng bỏ qua release. Nhánh `en` lại `CFRelease(langRef)` dù chuỗi
   này là phần tử mượn từ mảng. SDK ghi rõ các property của
   `TISGetInputSourceProperty` theo Get rule, không được tự release.
   Cần cân bằng ownership trên mọi nhánh và có test tiếng Anh,
   tiếng Việt/ngôn ngữ khác, NULL và mảng rỗng. Chưa đo lượng leak của
   nhánh này; nó được tắt trong phép đo trên.
3. **Dọn tài nguyên khi sleep/wake.** `OpenKeyInit` tạo event source và
   hai backspace events, còn `stopEventTap` chỉ dọn tap/run-loop source.
   Lần init tiếp theo ghi đè các reference đó. Cần bổ sung teardown
   tương ứng và kiểm thử nhiều vòng sleep/wake, init thất bại, stop
   lặp lại. Chưa đo lượng RAM tích lũy thực tế.
4. **Giới hạn lịch sử gõ nếu cần.** Engine lưu các từ của dòng vào
   `_typingStates` để phục hồi khi backspace; chỉ clear khi ngắt dòng,
   điều hướng hoặc tác vụ khác. Dòng cực dài có thể giữ nhiều trạng
   thái. Cần đo riêng rồi mới chọn giới hạn vì giới hạn làm thay đổi
   khả năng phục hồi khi xóa ngược qua nhiều từ.

## Công nghệ phù hợp

- **Giữ C++ và AppKit, tối ưu tích hợp:** engine hiện đã là mã native
  và rất nhẹ trong phép đo. Thay toàn bộ bằng Swift/Rust chưa có bằng
  chứng sẽ giảm RAM/CPU. Rust có thể hỗ trợ kiểm soát ownership, nhưng
  vẫn cần quản lý đúng các API Core Foundation qua FFI.
- **SMAppService.mainApp:** API từ macOS 13 cho đăng ký chính ứng dụng
  chạy cùng máy. Có thể thay helper chỉ dùng để mở app chính; cần xử
  lý đăng ký cũ và quyền Login Items khi chuyển. Lợi ích RAM chưa đo.
- **InputMethodKit:** framework chính thức cho bộ gõ hệ thống, có từ
  macOS 10.5, không phải công nghệ vừa xuất hiện. Cho phép tái sử dụng
  engine C++ và giao tiếp theo session văn bản thay vì dựa hoàn toàn
  vào global event tap/backspace giả lập. Đây là thay đổi kiến trúc:
  phải kiểm tra marked text, underline, phím tắt và tương thích Safari,
  Chrome, VS Code, Telegram trước khi chọn. Chưa có prototype hoặc
  số đo để kết luận nó tiết kiệm hơn OpenKey hiện tại.

Ưu tiên: giảm truy vấn cửa sổ trùng và sửa ownership/teardown trước;
đánh giá InputMethodKit bằng prototype riêng nếu muốn đổi trải nghiệm
bộ gõ. Bản đã cài vẫn là bản phục hồi timeout, không phải bản tối ưu mới.

## Tài liệu chính thức

- [CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:))
- [Core Foundation ownership](https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFMemoryMgmt/Concepts/Ownership.html)
- [InputMethodKit](https://developer.apple.com/documentation/inputmethodkit)
- [SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)

Quy tắc property của TIS được đối chiếu trực tiếp trong SDK Xcode:
`Carbon.framework/Frameworks/HIToolbox.framework/Headers/TextInputSources.h`.
