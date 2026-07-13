// AudioBackend: recitation audio playback for the Quran view.
//
// Wraps QMediaPlayer to play verse-by-verse recitation audio (cached to
// disk on demand via QuranBackend::audioFilePath). Supports:
//   - Off:        play the current verse once, then stop.
//   - RepeatVerse: repeat the current verse forever until stopped.
//   - RepeatRange: play forward verse-by-verse through a range (default:
//                  the whole Quran) and wrap back to the start of the
//                  range when it reaches the end - i.e. "play forever
//                  until stopped".
//
// Playback runs via the system GStreamer/Qt Multimedia pipeline and is
// NOT tied to window visibility, so it keeps playing if the screen dims
// or the QML view changes - as long as the roohaniye-shell PROCESS is
// still running. If the device fully suspends to RAM (not just screen
// blanking), all processes stop including this one; only screen-off
// blanking is something app-level code can survive. That distinction
// matters for the "keep playing even when the tablet is turned off"
// requirement and needs a system-level (not app-level) decision about
// whether the device is allowed to suspend at all while reciting.
#pragma once

#include <QObject>
#include <QMediaPlayer>
#include <QVariantList>

class QuranBackend;

class AudioBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)
    Q_PROPERTY(int currentSurah READ currentSurah NOTIFY currentVerseChanged)
    Q_PROPERTY(int currentAyah READ currentAyah NOTIFY currentVerseChanged)
    Q_PROPERTY(QString currentReciterId READ currentReciterId NOTIFY reciterChanged)
    Q_PROPERTY(int loopMode READ loopMode NOTIFY loopModeChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(bool usingPlaylist READ usingPlaylist NOTIFY playlistChanged)
    Q_PROPERTY(int playlistLength READ playlistLength NOTIFY playlistChanged)
    Q_PROPERTY(int playlistPosition READ playlistPosition NOTIFY playlistChanged)

public:
    enum LoopMode { Off = 0, RepeatVerse = 1, RepeatRange = 2 };
    Q_ENUM(LoopMode)

    explicit AudioBackend(QuranBackend *quranBackend, QObject *parent = nullptr);

    bool playing() const;
    int currentSurah() const { return m_surah; }
    int currentAyah() const { return m_ayah; }
    QString currentReciterId() const { return m_reciterId; }
    int loopMode() const { return m_loopMode; }
    qint64 position() const;
    qint64 duration() const;
    bool usingPlaylist() const { return m_usingPlaylist; }
    int playlistLength() const { return m_playlist.size(); }
    int playlistPosition() const { return m_playlistPos; }

    Q_INVOKABLE void playVerse(int surah, int ayah, const QString &reciterId);
    Q_INVOKABLE void pause();
    Q_INVOKABLE void resume();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(qint64 ms);
    Q_INVOKABLE void setLoopMode(int mode);
    // rangeEndSurah/Ayah of (0,0) means "no end" i.e. the whole Quran.
    Q_INVOKABLE void setRange(int startSurah, int startAyah, int endSurah, int endAyah);
    Q_INVOKABLE void clearRange();
    // Switch reciter without stopping the current playback session; if
    // something is currently playing, restarts the current verse with
    // the new reciter's audio.
    Q_INVOKABLE void setReciter(const QString &reciterId);

    // ---- Multi-select "playlist" playback (juz/surah/ayah selection) ----
    // `verses` is an ordered list of {surah,ayah} maps, typically produced
    // by QuranBackend::versesForSelection(). Starts playing the first
    // entry immediately. While a playlist is active, playback advances
    // through the list on each verse's end rather than sequentially
    // through the whole Quran; loopMode still applies (RepeatVerse repeats
    // the current playlist entry, anything else loops the whole list
    // forever - Off stops after one full pass through the list).
    Q_INVOKABLE void playSelection(const QVariantList &verses, const QString &reciterId);
    // Drops the active playlist (e.g. when the user presses stop), so
    // ordinary single-verse/range playback resumes normal behavior.
    Q_INVOKABLE void clearSelection();

signals:
    void playingChanged();
    void currentVerseChanged();
    void reciterChanged();
    void loopModeChanged();
    void positionChanged();
    void durationChanged();
    void playlistChanged();
    // Emitted whenever playback error occurs (e.g. no audio for this
    // verse+reciter combo) so QML can show a message instead of silently
    // doing nothing.
    void playbackError(const QString &message);

private slots:
    void onMediaStatusChanged(QMediaPlayer::MediaStatus status);

private:
    void loadAndPlay(int surah, int ayah);
    void advanceToNextVerse();
    void advancePlaylist();

    QuranBackend *m_quranBackend;
    QMediaPlayer *m_player;

    int m_surah = 1;
    int m_ayah = 1;
    QString m_reciterId;
    int m_loopMode = Off;

    bool m_hasRange = false;
    int m_rangeStartSurah = 1;
    int m_rangeStartAyah = 1;
    int m_rangeEndSurah = 114;
    int m_rangeEndAyah = 6;

    bool m_usingPlaylist = false;
    QVariantList m_playlist;
    int m_playlistPos = -1;
};
