import UIKit

/// Server address + email/username + password login, with an MFA field that appears only when
/// the server asks for one.
final class LoginViewController: UIViewController, UITextFieldDelegate {
    var onLoggedIn: (() -> Void)?

    private let serverField = UITextField()
    private let loginField = UITextField()
    private let passwordField = UITextField()
    private let mfaField = UITextField()
    private let button = UIButton(configuration: .borderedProminent())
    private let errorLabel = UILabel()
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        // The official login screen (`screens/login`), in the default Denim theme until yours loads.
        Theme.current = .denim
        let theme = Theme.current
        view.backgroundColor = theme.centerChannelBg
        overrideUserInterfaceStyle = .light

        configure(serverField, placeholder: "Server URL (e.g. chat.example.com)", content: .URL)
        serverField.keyboardType = .URL
        if ServerConfig.hasServer { serverField.text = ServerConfig.baseURL.absoluteString }
        let title = UILabel("Log In to Your Account", Typography.style(.heading, 1000), color: theme.centerChannelColor, lines: 0)
        let subtitle = UILabel("Enter your login details below.", Typography.style(.body, 200),
                               color: theme.centerChannelColor.opacity(0.72), lines: 0)

        configure(loginField, placeholder: "Email or Username", content: .username)
        loginField.keyboardType = .emailAddress
        configure(passwordField, placeholder: "Password", content: .password)
        passwordField.isSecureTextEntry = true
        configure(mfaField, placeholder: "Enter MFA Token", content: .oneTimeCode)
        mfaField.keyboardType = .numberPad
        mfaField.isHidden = true

        var titleText = AttributedString("Log In")
        titleText.font = Typography.style(.body, 200, .semibold).font
        button.configuration?.attributedTitle = titleText
        button.configuration?.buttonSize = .large
        button.configuration?.baseBackgroundColor = theme.buttonBg
        button.configuration?.baseForegroundColor = theme.buttonColor
        button.configuration?.background.cornerRadius = 4
        button.configuration?.cornerStyle = .fixed
        button.addAction(UIAction { [weak self] _ in self?.submit() }, for: .primaryActionTriggered)

        errorLabel.textColor = theme.errorTextColor
        errorLabel.font = Typography.style(.body, 75).font
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        let forgot = UIButton(type: .system)
        forgot.setAttributedTitle(NSAttributedString(string: "Forgot your password?", attributes:
            Typography.style(.body, 100, .semibold).attributes(color: theme.buttonBg)), for: .normal)
        forgot.contentHorizontalAlignment = .leading
        forgot.addAction(UIAction { [weak self] _ in
            guard let url = ServerConfig.normalize(self?.serverField.text ?? "") else { self?.show(error: "Enter your server's address first."); return }
            UIApplication.shared.open(url.appendingPathComponent("reset_password"))
        }, for: .primaryActionTriggered)

        [title, subtitle, serverField, loginField, passwordField, mfaField, errorLabel, forgot, button].forEach(stack.addArrangedSubview)
        stack.axis = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(12, after: title)
        stack.setCustomSpacing(32, after: subtitle)
        stack.setCustomSpacing(8, after: passwordField)
        stack.setCustomSpacing(24, after: forgot)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 80),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            // Readable width on the Duo's inner screen; full width (minus margins) on the outer one.
            stack.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            stack.widthAnchor.constraint(lessThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
            {
                let c = stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
                c.priority = .defaultHigh
                return c
            }(),
        ])
    }

    private func configure(_ field: UITextField, placeholder: String, content: UITextContentType) {
        field.placeholder = placeholder
        field.textContentType = content
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        let theme = Theme.current
        field.borderStyle = .none
        field.layer.cornerRadius = 4
        field.layer.borderWidth = 1
        field.layer.borderColor = theme.centerChannelColor.opacity(0.16).cgColor
        field.textColor = theme.centerChannelColor
        field.tintColor = theme.buttonBg
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: theme.centerChannelColor.opacity(0.64)])
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        field.leftViewMode = .always
        field.font = Typography.style(.body, 200).font
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .go
        field.delegate = self
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === serverField { loginField.becomeFirstResponder() }
        else if textField === loginField { passwordField.becomeFirstResponder() } else { submit() }
        return true
    }

    private func submit() {
        let login = (loginField.text ?? "").trimmingCharacters(in: .whitespaces)
        let password = passwordField.text ?? ""
        guard let server = ServerConfig.normalize(serverField.text ?? "") else {
            show(error: "Enter your server's address, like chat.example.com.")
            return
        }
        guard !login.isEmpty, !password.isEmpty else { return }
        if server != ServerConfig.baseURL { DiskCache.clear() }   // don't show another server's cache
        do { try ServerConfig.setServer(server) } catch { show(error: "Couldn't save the server address."); return }
        let mfa = mfaField.isHidden ? nil : mfaField.text
        setBusy(true)
        Task {
            do {
                try await AppSession.shared.login(loginId: login, password: password, mfaCode: mfa)
                view.endEditing(true)
                onLoggedIn?()
            } catch let error as APIError where error.id?.contains("mfa") == true && mfaField.isHidden {
                mfaField.isHidden = false
                mfaField.becomeFirstResponder()
                show(error: "To complete the sign in process, please enter the code from your mobile device's authenticator app.")
            } catch let error as APIError {
                show(error: error.message)
            } catch {
                show(error: error.localizedDescription)
            }
            setBusy(false)
        }
    }

    private func setBusy(_ busy: Bool) {
        button.configuration?.showsActivityIndicator = busy
        button.isEnabled = !busy
    }

    private func show(error: String) {
        errorLabel.text = error
        errorLabel.isHidden = false
    }
}

extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        UIFont(descriptor: fontDescriptor.withSymbolicTraits(traits) ?? fontDescriptor, size: 0)
    }
}
