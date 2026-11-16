import AppKit

/// Carries a pop-up item's value as an Objective-C object so AppKit stores it
/// untouched. A Swift value put straight into `representedObject` is bridged:
/// `nil` comes back as `NSNull` and a `String` as `NSString`, and lookups miss.
final class DropdownValueBox: NSObject {
    let value: AnyHashable

    init(_ value: AnyHashable) {
        self.value = value
    }
}

extension NSPopUpButton {
    /// The index of the item carrying `value`, if any.
    func indexOfItem(withBoxedValue value: AnyHashable) -> Int? {
        itemArray.firstIndex { ($0.representedObject as? DropdownValueBox)?.value == value }
    }

    /// The selected item's value, if it carries one.
    var selectedBoxedValue: AnyHashable? {
        (selectedItem?.representedObject as? DropdownValueBox)?.value
    }
}
