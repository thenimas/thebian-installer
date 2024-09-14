#!/bin/bash

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

flatpak install com.github.PintaProject.Pinta com.github.tchx84.Flatseal com.gluonhq.SceneBuilder com.obsproject.Studio com.spotify.Client dev.vencord.Vesktop org.kde.krita org.libreoffice.LibreOffice org.mozilla.Thunderbird org.mozilla.firefox
