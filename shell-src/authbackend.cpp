#include "authbackend.h"

#include <QPasswordDigestor>
#include <QRandomGenerator>
#include <QFile>
#include <QFileInfo>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QVector>

static const char *ACCOUNTS_PATH = "/opt/roohaniye/data/accounts.dat";
static const int PBKDF2_ITERATIONS = 210000; // OWASP 2023 minimum for PBKDF2-HMAC-SHA256
static const int SALT_BYTES = 16;
static const int HASH_BYTES = 32;

AuthBackend::AuthBackend(QObject *parent)
    : QObject(parent)
    , m_settings(QString::fromLatin1(ACCOUNTS_PATH), QSettings::IniFormat)
{
    m_autoLockMinutes = m_settings.value("auth/autoLockMinutes", 5).toInt();

    // If there are no accounts yet, there's nothing to lock behind -
    // start unlocked so a fresh Try/install session isn't blocked by a
    // login screen nobody set up.
    m_locked = hasAccounts();

    m_inactivityTimer.setSingleShot(true);
    connect(&m_inactivityTimer, &QTimer::timeout, this, [this]() {
        if (!m_loggedInUser.isEmpty() && m_autoLockMinutes > 0) {
            lockNow();
        }
    });
    resetInactivityTimer();

    if (qApp) {
        qApp->installEventFilter(this);
    }
}

bool AuthBackend::eventFilter(QObject *watched, QEvent *event)
{
    switch (event->type()) {
    case QEvent::MouseButtonPress:
    case QEvent::MouseMove:
    case QEvent::TouchBegin:
    case QEvent::TouchUpdate:
    case QEvent::KeyPress:
        noteActivity();
        break;
    default:
        break;
    }
    return QObject::eventFilter(watched, event);
}

void AuthBackend::noteActivity()
{
    resetInactivityTimer();
}

void AuthBackend::resetInactivityTimer()
{
    m_inactivityTimer.stop();
    if (m_autoLockMinutes > 0 && !m_loggedInUser.isEmpty()) {
        m_inactivityTimer.start(m_autoLockMinutes * 60 * 1000);
    }
}

void AuthBackend::restrictFilePermissions() const
{
    // Owner read/write only. Best-effort - if the filesystem doesn't
    // support POSIX permissions this silently no-ops, which is fine
    // since the underlying data (PBKDF2 hash + salt) isn't recoverable
    // to a plaintext password anyway.
    QFile::setPermissions(QString::fromLatin1(ACCOUNTS_PATH),
        QFileDevice::ReadOwner | QFileDevice::WriteOwner);
}

QByteArray AuthBackend::deriveHashStatic(const QString &password, const QByteArray &salt)
{
    return QPasswordDigestor::deriveKeyPbkdf2(
        QCryptographicHash::Sha256,
        password.toUtf8(),
        salt,
        PBKDF2_ITERATIONS,
        HASH_BYTES);
}

QByteArray AuthBackend::randomSalt()
{
    QByteArray salt;
    salt.resize(SALT_BYTES);
    for (int i = 0; i < SALT_BYTES; ++i) {
        salt[i] = static_cast<char>(QRandomGenerator::global()->bounded(256));
    }
    return salt;
}

QString AuthBackend::generateRecoveryCode()
{
    // 12 chars from an unambiguous alphabet (no 0/O/1/I/l), grouped for
    // readability: XXXX-XXXX-XXXX. ~62 bits of entropy - plenty for a
    // one-time local-recovery secret that's rate-limited by nothing
    // stopping repeated attempts today, so err on the generous side.
    static const QString alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
    QString code;
    for (int i = 0; i < 12; ++i) {
        if (i == 4 || i == 8) code += '-';
        code += alphabet.at(QRandomGenerator::global()->bounded(alphabet.size()));
    }
    return code;
}

QVector<AuthBackend::Account> AuthBackend::loadAccounts() const
{
    QVector<Account> accounts;
    int size = m_settings.beginReadArray("accounts");
    for (int i = 0; i < size; ++i) {
        m_settings.setArrayIndex(i);
        Account a;
        a.username = m_settings.value("username").toString();
        a.salt = QByteArray::fromBase64(m_settings.value("salt").toByteArray());
        a.hash = QByteArray::fromBase64(m_settings.value("hash").toByteArray());
        a.isAdmin = m_settings.value("isAdmin", false).toBool();
        a.recoverySalt = QByteArray::fromBase64(m_settings.value("recoverySalt").toByteArray());
        a.recoveryHash = QByteArray::fromBase64(m_settings.value("recoveryHash").toByteArray());
        if (!a.username.isEmpty()) {
            accounts.append(a);
        }
    }
    m_settings.endArray();
    return accounts;
}

void AuthBackend::saveAccounts(const QVector<Account> &accounts)
{
    m_settings.beginWriteArray("accounts");
    for (int i = 0; i < accounts.size(); ++i) {
        m_settings.setArrayIndex(i);
        m_settings.setValue("username", accounts[i].username);
        m_settings.setValue("salt", accounts[i].salt.toBase64());
        m_settings.setValue("hash", accounts[i].hash.toBase64());
        m_settings.setValue("isAdmin", accounts[i].isAdmin);
        m_settings.setValue("recoverySalt", accounts[i].recoverySalt.toBase64());
        m_settings.setValue("recoveryHash", accounts[i].recoveryHash.toBase64());
    }
    m_settings.endArray();
    m_settings.sync();
    restrictFilePermissions();
    emit accountsChanged();
}

bool AuthBackend::hasAccounts() const
{
    int count = m_settings.beginReadArray("accounts");
    m_settings.endArray();
    return count > 0;
}

QVariantMap AuthBackend::createAccount(const QString &username, const QString &password, bool isAdmin)
{
    QVariantMap result;
    QString uname = username.trimmed();

    if (uname.isEmpty()) {
        result["ok"] = false;
        result["error"] = "Username can't be empty.";
        return result;
    }
    if (password.size() < 4) {
        result["ok"] = false;
        result["error"] = "Password must be at least 4 characters.";
        return result;
    }

    QVector<Account> accounts = loadAccounts();
    bool isFirstAccount = accounts.isEmpty();

    // Server-side re-check: creating additional accounts requires an
    // active admin session. Never trust the QML-side gate alone.
    if (!isFirstAccount && !m_loggedInIsAdmin) {
        result["ok"] = false;
        result["error"] = "Only an admin can create additional accounts.";
        return result;
    }

    for (const Account &a : accounts) {
        if (a.username.compare(uname, Qt::CaseInsensitive) == 0) {
            result["ok"] = false;
            result["error"] = "That username already exists.";
            return result;
        }
    }

    Account newAccount;
    newAccount.username = uname;
    newAccount.salt = randomSalt();
    newAccount.hash = deriveHash(password, newAccount.salt);
    // First account ever created is always admin - guarantees the
    // install never ends up with zero admin accounts.
    newAccount.isAdmin = isFirstAccount ? true : isAdmin;

    QString recoveryCode = generateRecoveryCode();
    newAccount.recoverySalt = randomSalt();
    newAccount.recoveryHash = deriveHash(recoveryCode, newAccount.recoverySalt);

    accounts.append(newAccount);
    saveAccounts(accounts);

    result["ok"] = true;
    result["error"] = "";
    // Shown to the user exactly once, right now - not retrievable
    // again (only regenerate-able, which invalidates this one).
    result["recoveryCode"] = recoveryCode;
    return result;
}

QVariantMap AuthBackend::regenerateRecoveryCode(const QString &username, const QString &password)
{
    QVariantMap result;
    QVector<Account> accounts = loadAccounts();
    for (Account &a : accounts) {
        if (a.username.compare(username.trimmed(), Qt::CaseInsensitive) == 0) {
            if (deriveHash(password, a.salt) != a.hash) {
                result["ok"] = false;
                result["error"] = "Current password is incorrect.";
                return result;
            }
            QString code = generateRecoveryCode();
            a.recoverySalt = randomSalt();
            a.recoveryHash = deriveHash(code, a.recoverySalt);
            saveAccounts(accounts);
            result["ok"] = true;
            result["error"] = "";
            result["recoveryCode"] = code;
            return result;
        }
    }
    result["ok"] = false;
    result["error"] = "User not found.";
    return result;
}

QVariantMap AuthBackend::recoverPassword(const QString &username, const QString &recoveryCode, const QString &newPassword)
{
    QVariantMap result;
    if (newPassword.size() < 4) {
        result["ok"] = false;
        result["error"] = "New password must be at least 4 characters.";
        return result;
    }
    QVector<Account> accounts = loadAccounts();
    for (Account &a : accounts) {
        if (a.username.compare(username.trimmed(), Qt::CaseInsensitive) == 0) {
            if (a.recoveryHash.isEmpty()) {
                result["ok"] = false;
                result["error"] = "No recovery code was ever set up for this account. Ask an admin to reset your password instead.";
                return result;
            }
            QByteArray attempt = deriveHash(recoveryCode.trimmed().toUpper(), a.recoverySalt);
            if (attempt != a.recoveryHash) {
                result["ok"] = false;
                result["error"] = "Recovery code is incorrect.";
                return result;
            }
            a.salt = randomSalt();
            a.hash = deriveHash(newPassword, a.salt);
            // Using a recovery code invalidates it (single-use), same
            // as any real recovery-code scheme - a fresh one must be
            // generated (from Settings, once logged back in) to use
            // this path again.
            QString freshCode = generateRecoveryCode();
            a.recoverySalt = randomSalt();
            a.recoveryHash = deriveHash(freshCode, a.recoverySalt);
            saveAccounts(accounts);
            result["ok"] = true;
            result["error"] = "";
            result["recoveryCode"] = freshCode;
            return result;
        }
    }
    result["ok"] = false;
    result["error"] = "User not found.";
    return result;
}

QVariantMap AuthBackend::exportAccountForInstall(const QString &username, const QString &password, bool isAdmin)
{
    // Static, standalone - deliberately does NOT touch this process's
    // own accounts.dat/QSettings. Called only by the installer wizard,
    // which serializes the result into a staging file that gets copied
    // onto the freshly-formatted TARGET disk, never applied to the
    // live/Try session running right now.
    QVariantMap result;
    QString uname = username.trimmed();
    if (uname.isEmpty()) {
        result["ok"] = false;
        result["error"] = "Username can't be empty.";
        return result;
    }
    if (password.size() < 4) {
        result["ok"] = false;
        result["error"] = "Password must be at least 4 characters.";
        return result;
    }
    QByteArray salt = randomSalt();
    QByteArray hash = deriveHashStatic(password, salt);
    QString recoveryCode = generateRecoveryCode();
    QByteArray recoverySalt = randomSalt();
    QByteArray recoveryHash = deriveHashStatic(recoveryCode, recoverySalt);

    result["ok"] = true;
    result["error"] = "";
    result["username"] = uname;
    result["isAdmin"] = isAdmin;
    result["salt"] = QString::fromLatin1(salt.toBase64());
    result["hash"] = QString::fromLatin1(hash.toBase64());
    result["recoverySalt"] = QString::fromLatin1(recoverySalt.toBase64());
    result["recoveryHash"] = QString::fromLatin1(recoveryHash.toBase64());
    result["recoveryCode"] = recoveryCode;
    return result;
}

QVariantMap AuthBackend::login(const QString &username, const QString &password)
{
    QVariantMap result;
    QVector<Account> accounts = loadAccounts();

    for (const Account &a : accounts) {
        if (a.username.compare(username.trimmed(), Qt::CaseInsensitive) == 0) {
            QByteArray attempt = deriveHash(password, a.salt);
            if (attempt == a.hash) {
                m_loggedInUser = a.username;
                m_loggedInIsAdmin = a.isAdmin;
                m_locked = false;
                resetInactivityTimer();
                emit sessionChanged();
                emit lockedChanged();
                result["ok"] = true;
                result["error"] = "";
                return result;
            }
            break;
        }
    }

    result["ok"] = false;
    result["error"] = "Incorrect username or password.";
    return result;
}

void AuthBackend::lockNow()
{
    if (m_loggedInUser.isEmpty()) {
        return; // nobody logged in, nothing to lock
    }
    m_locked = true;
    m_inactivityTimer.stop();
    emit lockedChanged();
}

QVariantMap AuthBackend::unlock(const QString &password)
{
    QVariantMap result;
    if (m_loggedInUser.isEmpty()) {
        result["ok"] = false;
        result["error"] = "No active session.";
        return result;
    }

    QVector<Account> accounts = loadAccounts();
    for (const Account &a : accounts) {
        if (a.username == m_loggedInUser) {
            if (deriveHash(password, a.salt) == a.hash) {
                m_locked = false;
                resetInactivityTimer();
                emit lockedChanged();
                result["ok"] = true;
                result["error"] = "";
                return result;
            }
            break;
        }
    }

    result["ok"] = false;
    result["error"] = "Incorrect password.";
    return result;
}

void AuthBackend::logout()
{
    m_loggedInUser.clear();
    m_loggedInIsAdmin = false;
    m_locked = hasAccounts();
    m_inactivityTimer.stop();
    emit sessionChanged();
    emit lockedChanged();
}

QVariantList AuthBackend::listUsers() const
{
    QVariantList list;
    for (const Account &a : loadAccounts()) {
        QVariantMap m;
        m["username"] = a.username;
        m["isAdmin"] = a.isAdmin;
        list.append(m);
    }
    return list;
}

QVariantMap AuthBackend::changePassword(const QString &username, const QString &oldPassword, const QString &newPassword)
{
    QVariantMap result;
    if (newPassword.size() < 4) {
        result["ok"] = false;
        result["error"] = "New password must be at least 4 characters.";
        return result;
    }

    // Must either be changing your own password (know the old one) or
    // be an admin changing someone else's (server-side re-check).
    bool isSelf = (username.compare(m_loggedInUser, Qt::CaseInsensitive) == 0);
    if (!isSelf && !m_loggedInIsAdmin) {
        result["ok"] = false;
        result["error"] = "Only an admin can change another user's password.";
        return result;
    }

    QVector<Account> accounts = loadAccounts();
    for (Account &a : accounts) {
        if (a.username.compare(username.trimmed(), Qt::CaseInsensitive) == 0) {
            if (isSelf) {
                if (deriveHash(oldPassword, a.salt) != a.hash) {
                    result["ok"] = false;
                    result["error"] = "Current password is incorrect.";
                    return result;
                }
            }
            QByteArray newSalt;
            newSalt.resize(SALT_BYTES);
            for (int i = 0; i < SALT_BYTES; ++i) {
                newSalt[i] = static_cast<char>(QRandomGenerator::global()->bounded(256));
            }
            a.hash = deriveHash(newPassword, newSalt);
            a.salt = newSalt;
            saveAccounts(accounts);
            result["ok"] = true;
            result["error"] = "";
            return result;
        }
    }

    result["ok"] = false;
    result["error"] = "User not found.";
    return result;
}

QVariantMap AuthBackend::deleteAccount(const QString &username, const QString &adminPassword)
{
    QVariantMap result;
    if (!m_loggedInIsAdmin) {
        result["ok"] = false;
        result["error"] = "Only an admin can delete accounts.";
        return result;
    }

    QVector<Account> accounts = loadAccounts();

    // Verify the acting admin's password (defense in depth - don't just
    // trust that a session being "logged in as admin" is enough for a
    // destructive action).
    bool adminVerified = false;
    for (const Account &a : accounts) {
        if (a.username == m_loggedInUser && deriveHash(adminPassword, a.salt) == a.hash) {
            adminVerified = true;
            break;
        }
    }
    if (!adminVerified) {
        result["ok"] = false;
        result["error"] = "Admin password incorrect.";
        return result;
    }

    int adminCount = 0;
    int targetIndex = -1;
    for (int i = 0; i < accounts.size(); ++i) {
        if (accounts[i].isAdmin) adminCount++;
        if (accounts[i].username.compare(username.trimmed(), Qt::CaseInsensitive) == 0) targetIndex = i;
    }

    if (targetIndex < 0) {
        result["ok"] = false;
        result["error"] = "User not found.";
        return result;
    }
    if (accounts[targetIndex].isAdmin && adminCount <= 1) {
        result["ok"] = false;
        result["error"] = "Can't delete the last admin account.";
        return result;
    }

    bool deletingSelf = (accounts[targetIndex].username == m_loggedInUser);
    accounts.remove(targetIndex);
    saveAccounts(accounts);

    if (deletingSelf) {
        logout();
    }

    result["ok"] = true;
    result["error"] = "";
    return result;
}

void AuthBackend::setAutoLockMinutes(int minutes)
{
    if (minutes < 0) minutes = 0;
    m_autoLockMinutes = minutes;
    m_settings.setValue("auth/autoLockMinutes", m_autoLockMinutes);
    m_settings.sync();
    resetInactivityTimer();
    emit autoLockMinutesChanged();
}
