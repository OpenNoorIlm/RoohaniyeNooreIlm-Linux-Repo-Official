cmake_minimum_required(VERSION 3.16)
project(roohaniye-shell LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt5 REQUIRED COMPONENTS Core Gui Qml Quick Network Sql Multimedia)

add_executable(roohaniye-shell
    main.cpp
    appcenter.cpp
    appcenter.h
    quranbackend.cpp
    quranbackend.h
    mushafbackend.cpp
    mushafbackend.h
    audiobackend.cpp
    audiobackend.h
    wifibackend.cpp
    wifibackend.h
    powerbackend.cpp
    powerbackend.h
    storagebackend.cpp
    storagebackend.h
    dbconnectorbackend.cpp
    dbconnectorbackend.h
    updatebackend.cpp
    updatebackend.h
    prayerbackend.cpp
    prayerbackend.h
    installerbackend.cpp
    installerbackend.h
    reminderbackend.cpp
    reminderbackend.h
    authbackend.cpp
    authbackend.h
    brightnessbackend.cpp
    brightnessbackend.h
    themebackend.cpp
    themebackend.h
    volumebackend.cpp
    volumebackend.h
    debugbackend.cpp
    debugbackend.h
    qml.qrc
)

target_link_libraries(roohaniye-shell
    Qt5::Core
    Qt5::Gui
    Qt5::Qml
    Qt5::Quick
    Qt5::Network
    Qt5::Sql
    Qt5::Multimedia
)

install(TARGETS roohaniye-shell DESTINATION /opt/roohaniye/bin)
