#!/usr/bin/env python3
"""
One-time migration: splits quran_audio_embedded.db into two files so that
text-only queries (surah list, verse text, navigation) never touch the
21GB+ of embedded mp3 audio blobs.

  quran_audio_embedded.db (~21.5GB)
      -> quran_text.db   (verses table only - small, hot path for reading)
      -> quran_audio.db  (audio_files + word_timings - large, only touched
                           during actual recitation playback)

Uses SQLite ATTACH + "INSERT INTO ... SELECT" so the copy happens entirely
inside the SQLite engine (including the audio BLOBs) - this script never
loads a verse row or an mp3 blob into Python memory itself.

Usage:
    python3 split_quran_db.py [--data-dir /opt/roohaniye/data] [--keep-original]

By default the original quran_audio_embedded.db is left in place untouched
(the shell won't reference it anymore once main.cpp is updated, but nothing
here deletes it automatically - remove it by hand once you've confirmed the
split databases work).
"""
import argparse
import os
import sqlite3
import sys
import time

VERSES_SCHEMA = """
CREATE TABLE verses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    surah INTEGER NOT NULL,
    ayah INTEGER NOT NULL,
    juz INTEGER,
    page INTEGER,
    sajda INTEGER,
    text_jalalayn TEXT,
    text_kanzuliman TEXT,
    text_sahih TEXT,
    text_uthmani TEXT,
    manzil INTEGER,
    ruku INTEGER,
    hizb_quarter INTEGER,
    sajda_obligatory INTEGER,
    UNIQUE(surah, ayah)
)
"""

AUDIO_FILES_SCHEMA = """
CREATE TABLE audio_files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    verse_id INTEGER NOT NULL,
    reciter_id TEXT NOT NULL,
    audio_data BLOB NOT NULL,
    UNIQUE(verse_id, reciter_id)
)
"""

WORD_TIMINGS_SCHEMA = """
CREATE TABLE word_timings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    verse_id INTEGER NOT NULL,
    reciter_id TEXT NOT NULL,
    timings_json TEXT NOT NULL,
    UNIQUE(verse_id, reciter_id)
)
"""


def table_count(con, db_alias, table):
    cur = con.execute(f"SELECT COUNT(*) FROM {db_alias}.{table}")
    return cur.fetchone()[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", default="/opt/roohaniye/data")
    ap.add_argument("--source", default=None,
                     help="Override full path to the source combined db")
    args = ap.parse_args()

    data_dir = args.data_dir
    source_path = args.source or os.path.join(data_dir, "quran_audio_embedded.db")
    text_path = os.path.join(data_dir, "quran_text.db")
    audio_path = os.path.join(data_dir, "quran_audio.db")

    if not os.path.exists(source_path):
        sys.exit(f"Source db not found: {source_path}")
    for out_path in (text_path, audio_path):
        if os.path.exists(out_path):
            sys.exit(f"Refusing to overwrite existing file: {out_path} "
                      f"(delete it first if you want to re-run the migration)")

    print(f"Source:      {source_path} ({os.path.getsize(source_path) / 1e9:.2f} GB)")
    print(f"Text out:    {text_path}")
    print(f"Audio out:   {audio_path}")

    con = sqlite3.connect(source_path)
    con.execute("PRAGMA journal_mode=OFF")  # scratch attached dbs, no crash-safety needed
    con.execute("PRAGMA synchronous=OFF")

    src_verses = con.execute("SELECT COUNT(*) FROM verses").fetchone()[0]
    src_audio = con.execute("SELECT COUNT(*) FROM audio_files").fetchone()[0]
    src_timings = con.execute("SELECT COUNT(*) FROM word_timings").fetchone()[0]
    print(f"\nSource row counts: verses={src_verses} audio_files={src_audio} "
          f"word_timings={src_timings}")

    # ---- 1. verses -> quran_text.db ----
    t0 = time.time()
    con.execute("ATTACH DATABASE ? AS textdb", (text_path,))
    con.execute(VERSES_SCHEMA.replace("CREATE TABLE verses", "CREATE TABLE textdb.verses"))
    con.execute("INSERT INTO textdb.verses SELECT * FROM verses")
    con.commit()
    out_verses = table_count(con, "textdb", "verses")
    con.execute("DETACH DATABASE textdb")
    print(f"verses copied: {out_verses} rows in {time.time() - t0:.1f}s")
    if out_verses != src_verses:
        sys.exit(f"MISMATCH: source had {src_verses} verses, copy has {out_verses}")

    # ---- 2. audio_files + word_timings -> quran_audio.db ----
    t0 = time.time()
    con.execute("ATTACH DATABASE ? AS audiodb", (audio_path,))
    con.execute(AUDIO_FILES_SCHEMA.replace("CREATE TABLE audio_files", "CREATE TABLE audiodb.audio_files"))
    con.execute(WORD_TIMINGS_SCHEMA.replace("CREATE TABLE word_timings", "CREATE TABLE audiodb.word_timings"))
    con.execute("INSERT INTO audiodb.audio_files SELECT * FROM audio_files")
    con.execute("INSERT INTO audiodb.word_timings SELECT * FROM word_timings")
    con.commit()
    out_audio = table_count(con, "audiodb", "audio_files")
    out_timings = table_count(con, "audiodb", "word_timings")
    con.execute("DETACH DATABASE audiodb")
    print(f"audio_files copied: {out_audio} rows, word_timings copied: {out_timings} rows "
          f"in {time.time() - t0:.1f}s")
    if out_audio != src_audio or out_timings != src_timings:
        sys.exit(f"MISMATCH: source had audio_files={src_audio} word_timings={src_timings}, "
                  f"copy has audio_files={out_audio} word_timings={out_timings}")

    con.close()

    # ---- 3. sanity check: re-open the two new files fresh and cross-check a join ----
    text_con = sqlite3.connect(text_path)
    audio_con = sqlite3.connect(audio_path)
    text_con.execute("ATTACH DATABASE ? AS audiodb", (audio_path,))
    joined = text_con.execute(
        "SELECT COUNT(*) FROM verses v JOIN audiodb.audio_files af ON af.verse_id = v.id"
    ).fetchone()[0]
    text_con.close()
    audio_con.close()
    print(f"\nCross-db join sanity check (verses x audio_files via ATTACH): {joined} rows "
          f"(expected {src_audio})")
    if joined != src_audio:
        sys.exit("MISMATCH: cross-db join didn't return the expected row count - "
                  "verse_id values may not line up between the two new files.")

    print(f"\nOK. New files:")
    print(f"  {text_path}  ({os.path.getsize(text_path) / 1e6:.1f} MB)")
    print(f"  {audio_path} ({os.path.getsize(audio_path) / 1e9:.2f} GB)")
    print(f"\nOriginal left untouched at {source_path} - delete it by hand once you've")
    print("confirmed the shell works correctly against the two new files.")


if __name__ == "__main__":
    main()
