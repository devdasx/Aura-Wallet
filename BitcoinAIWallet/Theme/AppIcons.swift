import SwiftUI

// MARK: - AppIcons
// Single source of truth for ALL SF Symbol references.
// NEVER hardcode SF Symbol strings in views — use AppIcons.

struct AppIcons {
    // MARK: - Navigation
    static let back = "chevron.left"
    static let close = "xmark"
    static let settings = "gearshape.fill"
    static let menu = "line.3.horizontal"

    // MARK: - Wallet Actions
    static let send = "arrow.up.circle.fill"
    static let receive = "arrow.down.circle.fill"
    static let scan = "qrcode.viewfinder"
    static let history = "clock.fill"
    static let fees = "gauge.medium"

    // MARK: - Transaction
    static let txSent = "arrow.up.right"
    static let txReceived = "arrow.down.left"
    static let txPending = "clock"
    static let txConfirmed = "checkmark.circle.fill"
    static let txFailed = "xmark.circle.fill"

    // MARK: - Security
    static let lock = "lock.fill"
    static let unlock = "lock.open.fill"
    static let faceID = "faceid"
    static let touchID = "touchid"
    static let shield = "shield.checkered"
    static let key = "key.fill"

    // MARK: - Status
    static let success = "checkmark.circle.fill"
    static let error = "exclamationmark.circle.fill"
    static let warning = "exclamationmark.triangle.fill"
    static let info = "info.circle.fill"

    // MARK: - Chat
    static let newChat = "square.and.pencil"
    static let sendMessage = "arrow.up.circle.fill"
    static let aiBot = "brain"
    static let user = "person.circle.fill"
    static let typing = "ellipsis"

    // MARK: - General
    static let copy = "doc.on.doc"
    static let share = "square.and.arrow.up"
    static let refresh = "arrow.clockwise"
    static let bitcoin = "bitcoinsign.circle.fill"
    static let wallet = "wallet.pass.fill"
    static let chevronRight = "chevron.right"
    static let chevronDown = "chevron.down"
    static let eye = "eye.fill"
    static let eyeSlash = "eye.slash.fill"
    static let trash = "trash.fill"
    static let network = "network"
    static let checkmark = "checkmark"
    static let plus = "plus"
    static let qrCode = "qrcode"
    static let globe = "globe"
    static let paintbrush = "paintbrush.fill"
}
