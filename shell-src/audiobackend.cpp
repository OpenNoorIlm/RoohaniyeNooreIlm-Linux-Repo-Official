#include "audiobackend.h"
#include "quranbackend.h"

#include <QUrl>
#include <QDebug>

AudioBackend::AudioBackend(QuranBackend *quranBackend, QObject *parent)
    : QObject(parent)
    , m_quranBackend(quranBackend)
    , m_player(new QMediaPlayer(this))
{
    connect(m_player, &QMediaPlayer::mediaStatusChanged,
            this, &AudioBackend::onMediaStatusChanged);
    connect(m_player, &QMediaPlayer::positionChanged,
            this, &AudioBackend::positionChanged);
    connect(m_player, &QMediaPlayer::durationChanged,
            this, &AudioBackend::durationChanged);
    connect(m_player, &QMediaPlayer::stateChanged, this, [this](QMediaPlayer::State) {
        emit playingChanged();
    });
    connect(m_player, QOverload<QMediaPlayer::Error>::of(&QMediaPlayer::error), this, [this](QMediaPlayer::Error) {
        emit playbackError(m_player->errorString());
    });
}

bool AudioBackend::playing() const
{
    return m_player->state() == QMediaPlayer::PlayingState;
}

qint64 AudioBackend::position() const { return m_player->position(); }
qint64 AudioBackend::duration() const { return m_player->duration(); }

void AudioBackend::loadAndPlay(int surah, int ayah)
{
    if (!m_quranBackend || m_reciterId.isEmpty()) return;

    const QString path = m_quranBackend->audioFilePath(surah, ayah, m_reciterId);
    if (path.isEmpty()) {
        emit playbackError(QString("No audio for %1:%2 with this reciter").arg(surah).arg(ayah));
        return;
    }

    m_surah = surah;
    m_ayah = ayah;
    emit currentVerseChanged();

    m_player->setMedia(QUrl::fromLocalFile(path));
    m_player->play();
}

void AudioBackend::playVerse(int surah, int ayah, const QString &reciterId)
{
    clearSelection();
    m_reciterId = reciterId;
    emit reciterChanged();
    loadAndPlay(surah, ayah);
}

void AudioBackend::pause()
{
    m_player->pause();
}

void AudioBackend::resume()
{
    m_player->play();
}

void AudioBackend::stop()
{
    m_player->stop();
    clearSelection();
}

void AudioBackend::seek(qint64 ms)
{
    m_player->setPosition(ms);
}

void AudioBackend::setLoopMode(int mode)
{
    if (m_loopMode == mode) return;
    m_loopMode = mode;
    emit loopModeChanged();
}

void AudioBackend::setRange(int startSurah, int startAyah, int endSurah, int endAyah)
{
    m_hasRange = true;
    m_rangeStartSurah = startSurah;
    m_rangeStartAyah = startAyah;
    m_rangeEndSurah = endSurah;
    m_rangeEndAyah = endAyah;
}

void AudioBackend::clearRange()
{
    m_hasRange = false;
    m_rangeStartSurah = 1;
    m_rangeStartAyah = 1;
    m_rangeEndSurah = 114;
    m_rangeEndAyah = 6;
}

void AudioBackend::playSelection(const QVariantList &verses, const QString &reciterId)
{
    if (verses.isEmpty()) return;

    m_playlist = verses;
    m_playlistPos = 0;
    m_usingPlaylist = true;
    emit playlistChanged();

    m_reciterId = reciterId;
    emit reciterChanged();

    const QVariantMap first = verses.first().toMap();
    loadAndPlay(first.value("surah").toInt(), first.value("ayah").toInt());
}

void AudioBackend::clearSelection()
{
    if (!m_usingPlaylist && m_playlist.isEmpty()) return;
    m_usingPlaylist = false;
    m_playlist.clear();
    m_playlistPos = -1;
    emit playlistChanged();
}

void AudioBackend::advancePlaylist()
{
    if (m_playlist.isEmpty()) return;

    m_playlistPos++;
    if (m_playlistPos >= m_playlist.size()) {
        if (m_loopMode == Off) {
            // Play through the selection once, then stop - same "Off"
            // semantics as single-verse playback.
            m_usingPlaylist = false;
            emit playlistChanged();
            return;
        }
        m_playlistPos = 0;
    }
    emit playlistChanged();

    const QVariantMap v = m_playlist.at(m_playlistPos).toMap();
    loadAndPlay(v.value("surah").toInt(), v.value("ayah").toInt());
}

void AudioBackend::setReciter(const QString &reciterId)
{
    if (m_reciterId == reciterId) return;
    m_reciterId = reciterId;
    emit reciterChanged();
    if (playing() || m_player->mediaStatus() != QMediaPlayer::NoMedia) {
        loadAndPlay(m_surah, m_ayah);
    }
}

void AudioBackend::onMediaStatusChanged(QMediaPlayer::MediaStatus status)
{
    if (status != QMediaPlayer::EndOfMedia) return;

    if (m_usingPlaylist) {
        if (m_loopMode == RepeatVerse) {
            m_player->setPosition(0);
            m_player->play();
            return;
        }
        advancePlaylist();
        return;
    }

    switch (m_loopMode) {
    case RepeatVerse:
        m_player->setPosition(0);
        m_player->play();
        break;
    case RepeatRange:
        advanceToNextVerse();
        break;
    case Off:
    default:
        // Played once, stop.
        break;
    }
}

void AudioBackend::advanceToNextVerse()
{
    if (!m_quranBackend) return;

    const int startSurah = m_hasRange ? m_rangeStartSurah : 1;
    const int startAyah = m_hasRange ? m_rangeStartAyah : 1;
    const int endSurah = m_hasRange ? m_rangeEndSurah : 114;
    const int endAyah = m_hasRange ? m_rangeEndAyah : 6;

    // Are we at (or past) the end of the range? Wrap to the start -
    // this is what makes RepeatRange effectively "play forever".
    if (m_surah > endSurah || (m_surah == endSurah && m_ayah >= endAyah)) {
        loadAndPlay(startSurah, startAyah);
        return;
    }

    const QVariantMap next = m_quranBackend->nextVerse(m_surah, m_ayah);
    if (next.isEmpty()) {
        loadAndPlay(startSurah, startAyah);
        return;
    }
    loadAndPlay(next.value("surah").toInt(), next.value("ayah").toInt());
}
