extension DetectionContext: Codable {
    private enum CodingKeys: String, CodingKey { case type, callee }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "textView":                self = .textView
        case "buttonLabel":             self = .buttonLabel
        case "labelView":               self = .labelView
        case "navigationTitle":         self = .navigationTitle
        case "alert":                   self = .alert
        case "confirmationDialog":      self = .confirmationDialog
        case "textField":               self = .textField
        case "accessibilityLabel":      self = .accessibilityLabel
        case "toggle":                  self = .toggle
        case "section":                 self = .section
        case "picker":                  self = .picker
        case "menu":                    self = .menu
        case "disclosureGroup":         self = .disclosureGroup
        case "helpText":                self = .helpText
        case "uiLabel":                 self = .uiLabel
        case "uiButtonTitle":           self = .uiButtonTitle
        case "uiTextFieldPlaceholder":  self = .uiTextFieldPlaceholder
        case "uiNavigationTitle":       self = .uiNavigationTitle
        case "uiAlertTitle":            self = .uiAlertTitle
        case "uiAlertMessage":          self = .uiAlertMessage
        case "uiAlertAction":           self = .uiAlertAction
        case "uiTabBarItem":            self = .uiTabBarItem
        case "staticStringConstant": self = .staticStringConstant
        default:
            let callee = (try? c.decodeIfPresent(String.self, forKey: .callee)) ?? type
            self = .unknownUIContext(callee: callee)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .textView:               try c.encode("textView",               forKey: .type)
        case .buttonLabel:            try c.encode("buttonLabel",            forKey: .type)
        case .labelView:              try c.encode("labelView",              forKey: .type)
        case .navigationTitle:        try c.encode("navigationTitle",        forKey: .type)
        case .alert:                  try c.encode("alert",                  forKey: .type)
        case .confirmationDialog:     try c.encode("confirmationDialog",     forKey: .type)
        case .textField:              try c.encode("textField",              forKey: .type)
        case .accessibilityLabel:     try c.encode("accessibilityLabel",     forKey: .type)
        case .toggle:                 try c.encode("toggle",                 forKey: .type)
        case .section:                try c.encode("section",                forKey: .type)
        case .picker:                 try c.encode("picker",                 forKey: .type)
        case .menu:                   try c.encode("menu",                   forKey: .type)
        case .disclosureGroup:        try c.encode("disclosureGroup",        forKey: .type)
        case .helpText:               try c.encode("helpText",               forKey: .type)
        case .uiLabel:                try c.encode("uiLabel",                forKey: .type)
        case .uiButtonTitle:          try c.encode("uiButtonTitle",          forKey: .type)
        case .uiTextFieldPlaceholder: try c.encode("uiTextFieldPlaceholder", forKey: .type)
        case .uiNavigationTitle:      try c.encode("uiNavigationTitle",      forKey: .type)
        case .uiAlertTitle:           try c.encode("uiAlertTitle",           forKey: .type)
        case .uiAlertMessage:         try c.encode("uiAlertMessage",         forKey: .type)
        case .uiAlertAction:          try c.encode("uiAlertAction",          forKey: .type)
        case .uiTabBarItem:           try c.encode("uiTabBarItem",           forKey: .type)
        case .unknownUIContext(let callee):
            try c.encode("unknownUIContext",     forKey: .type)
            try c.encode(callee,                 forKey: .callee)
        case .staticStringConstant:
            try c.encode("staticStringConstant", forKey: .type)
        }
    }
}
