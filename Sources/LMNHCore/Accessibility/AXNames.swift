import Foundation

public enum AXNames {
    public enum Attribute {
        public static let role = "AXRole"
        public static let subrole = "AXSubrole"
        public static let roleDescription = "AXRoleDescription"
        public static let title = "AXTitle"
        public static let description = "AXDescription"
        public static let help = "AXHelp"
        public static let value = "AXValue"
        public static let placeholderValue = "AXPlaceholderValue"
        public static let enabled = "AXEnabled"
        public static let focused = "AXFocused"
        public static let selected = "AXSelected"
        public static let position = "AXPosition"
        public static let size = "AXSize"
        public static let frame = "AXFrame"
        public static let children = "AXChildren"
        public static let visibleChildren = "AXVisibleChildren"
        public static let childrenInNavigationOrder = "AXChildrenInNavigationOrder"
    }

    public enum Action {
        public static let press = "AXPress"
        public static let showMenu = "AXShowMenu"
        public static let confirm = "AXConfirm"
        public static let cancel = "AXCancel"
        public static let raise = "AXRaise"
        public static let increment = "AXIncrement"
        public static let decrement = "AXDecrement"
        public static let pick = "AXPick"
        public static let showDefaultUI = "AXShowDefaultUI"
    }

    public enum Role {
        public static let window = "AXWindow"
    }
}
