// AuthBackend: username/password accounts with PBKDF2-HMAC-SHA256
// password hashing (QPasswordDigestor, Qt's built-in implementation -
// no plaintext password is ever written to disk, logged, or held in
// memory longer than the single verifyLogin()/unlock() call needs it).
//
// Storage is a DEDICATED file, separate from shell_settings.ini (which
// every other backend uses and which isn't secrets-sensitive) -
// /opt/roohaniye/data/accounts.dat, permissions forced to 0600
// (owner read/write only) after every write, so other local accounts on
// the same machine can't read the hash/salt file even though they can't
// do much with a PBKDF2 hash anyway. This is the realistic ceiling for
// "very securely" in a single-process embedded shell with no OS-level
// user separation or system keyring integration - documented plainly
// here and in continue.md rather than oversold as bank-grade.
//
// Honest limits, on purpose, not oversights:
//  - This gates the SHELL UI, not the Linux user account/disk itself -
//    someone with physical access and a live USB can still read the
//    disk. That's a much bigger scope (full-disk encryption at install
//    time) and wasn't asked for here.
//  - No accounts ever created (fresh Try session, or install without
//    setting one up) = hasAccounts() is false = the lock screen never
//    shows, by design. Locking is opt-in via the installer/Settings,
//    never forced on a live/demo session.
#pragma once

#include <QObject>
#include <QString>
#include <QSettings>
#include <QVariantMap>
#include <QVariantList>
#include <QTimer>
#include <QEvent>

class AuthBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool hasAccounts READ hasAccounts NOTIFY accountsChanged)
    Q_PROPERTY(QString loggedInUser READ loggedInUser NOTIFY sessionChanged)
    Q_PROPERTY(bool loggedInIsAdmin READ loggedInIsAdmin NOTIFY sessionChanged)
    Q_PROPERTY(bool locked READ locked NOTIFY lockedChanged)
    Q_PROPERTY(int autoLockMinutes READ autoLockMinutes NOTIFY autoLockMinutesChanged)

public:
    explicit AuthBackend(QObject *parent = nullptr);

    bool hasAccounts() const;
    QString loggedInUser() const { return m_loggedInUser; }
    bool loggedInIsAdmin() const { return m_loggedInIsAdmin; }
    bool locked() const { return m_locked; }
    int autoLockMinutes() const { return m_autoLockMinutes; }

    // { ok: bool, error: string }. First account ever created is always
    // admin, regardless of the isAdmin argument, so there's never a
    // zero-admin install. Requires an active admin session to create
    // FURTHER accounts (checked by the caller in QML via
    // loggedInIsAdmin - also re-checked here server-side, never trust
    // the UI alone).
    Q_INVOKABLE QVariantMap createAccount(const QString &username, const QString &password, bool isAdmin);
    Q_INVOKABLE QVariantMap login(const QString &username, const QString &password);
    Q_INVOKABLE void lockNow();
    Q_INVOKABLE QVariantMap unlock(const QString &password); // checks against loggedInUser
    Q_INVOKABLE void logout();
    Q_INVOKABLE QVariantList listUsers() const; // [{ username, isAdmin }], no hashes/salts exposed to QML ever
    Q_INVOKABLE QVariantMap changePassword(const QString &username, const QString &oldPassword, const QString &newPassword);
    Q_INVOKABLE QVariantMap deleteAccount(const QString &username, const QString &adminPassword);
    Q_INVOKABLE void setAutoLockMinutes(int minutes); // 0 = never auto-lock

    // --- Password recovery (no email/SMS on this device, so recovery
    // is a one-time code shown ONCE at account-creation time, which the
    // user is told to write down). { ok, error, recoveryCode } - the
    // code is only ever returned in plaintext here, at creation. It's
    // stored only as a salted PBKDF2 hash, same as the password.
    Q_INVOKABLE QVariantMap regenerateRecoveryCode(const QString &username, const QString &password); // requires current password, returns a fresh code (invalidates the old one)
    Q_INVOKABLE QVariantMap recoverPassword(const QString &username, const QString &recoveryCode, const QString &newPassword);

    // Used ONLY by the installer wizard's optional "create an account"
    // step, which runs before the target disk even has a shell process
    // of its own - there is no live session to log into, so this must
    // not touch this process's own accounts.dat (that would lock the
    // CURRENT Try/live session, which must never happen implicitly).
    // Returns a plain (non-secret-holding) map the installer serializes
    // into a staging file and copies onto the freshly-partitioned
    // target disk as its accounts.dat during install.
    Q_INVOKABLE static QVariantMap exportAccountForInstall(const QString &username, const QString &password, bool isAdmin);
    // Called from a global, app-wide event filter (see main.cpp) on any
    // mouse/touch/key activity - resets the inactivity countdown. Also
    // safe to call directly from QML (e.g. on an explicit "I'm still
    // here" interaction) though the event filter already covers taps.
    Q_INVOKABLE void noteActivity();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

signals:
    void accountsChanged();
    void sessionChanged();
    void lockedChanged();
    void autoLockMinutesChanged();

private:
    struct Account {
        QString username;
        QByteArray salt;
        QByteArray hash;
        bool isAdmin;
        QByteArray recoverySalt;
        QByteArray recoveryHash; // empty if no recovery code was ever generated
    };

    QVector<Account> loadAccounts() const;
    void saveAccounts(const QVector<Account> &accounts);
    static QByteArray deriveHashStatic(const QString &password, const QByteArray &salt);
    QByteArray deriveHash(const QString &password, const QByteArray &salt) const { return deriveHashStatic(password, salt); }
    void restrictFilePermissions() const;
    void resetInactivityTimer();
    static QString generateRecoveryCode(); // human-typeable, e.g. "ROOH-7F3K-9QXZ"
    static QByteArray randomSalt();

    mutable QSettings m_settings; // beginReadArray/endArray are non-const in Qt but loadAccounts()/hasAccounts() are logically read-only
    QString m_loggedInUser;
    bool m_loggedInIsAdmin = false;
    bool m_locked = true;
    int m_autoLockMinutes = 5;
    QTimer m_inactivityTimer;
};
