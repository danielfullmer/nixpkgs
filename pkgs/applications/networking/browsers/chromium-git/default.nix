{ stdenv, stdenvNoCC, lib, fetchgit, fetchurl, runCommand
, python2, gn, ninja, llvmPackages_9, nodejs, jre8, bison, gperf, pkg-config, protobuf
, dbus, systemd, glibc, at-spi2-atk, atk, at-spi2-core, nspr, nss, pciutils, utillinux, kerberos, gdk-pixbuf
, glib, gtk3, alsaLib, pulseaudio, xdg_utils, libXScrnSaver, libXcursor, libXtst, libGLU_combined, libXdamage
, customGnFlags ? {}
}:

let
  # Serialize Nix types into GN types according to this document:
  # https://gn.googlesource.com/gn/+/refs/heads/master/docs/language.md
  gnToString =
    let
      mkGnString = value: "\"${lib.escape ["\"" "$" "\\"] value}\"";
      sanitize = value:
        if value == true then "true"
        else if value == false then "false"
        else if lib.isList value then "[${lib.concatMapStringsSep ", " sanitize value}]"
        else if lib.isInt value then toString value
        else if lib.isString value then mkGnString value
        else throw "Unsupported type for GN value `${value}'.";
      toFlag = key: value: "${key}=${sanitize value}";
    in
      attrs: lib.concatStringsSep " " (lib.attrValues (lib.mapAttrs toFlag attrs));

  # https://gitlab.com/noencoding/OS-X-Chromium-with-proprietary-codecs/wikis/List-of-all-gn-arguments-for-Chromium-build
  gnFlags = {
    is_debug = false;
    use_jumbo_build = true; # at least 2X compilation speedup

    proprietary_codecs = false;
    enable_nacl = false;
    is_component_build = true;
    is_clang = true;
    clang_use_chrome_plugins = false;

    # Google API keys, see:
    #   http://www.chromium.org/developers/how-tos/api-keys
    # Note: These are for NixOS/nixpkgs use ONLY. For your own distribution,
    # please get your own set of keys.
    google_api_key = "AIzaSyDGi15Zwl11UNe6Y-5XW_upsfyw31qwZPI";
    google_default_client_id = "404761575300.apps.googleusercontent.com";
    google_default_client_secret = "9rIFQjfnkykEmqb6FfjJQD1D";

    linux_use_bundled_binutils = false;
    treat_warnings_as_errors = false;
    use_sysroot = false;
    use_gio = true;
    use_gnome_keyring = false;
    use_lld = false;
    use_gold = false;
    use_pulseaudio = true;
    enable_widevine = false;
    enable_swiftshader = false;
    
    # explicit host_cpu and target_cpu prevent "nix-shell pkgsi686Linux.chromium-git" from building x86_64 version
    # there is no problem with nix-build, but platform detection in nix-shell is not correct
    host_cpu   = { i686-linux = "x86"; x86_64-linux = "x64"; armv7l-linux = "arm"; aarch64-linux = "arm64"; }.${stdenv.buildPlatform.system};
    target_cpu = { i686-linux = "x86"; x86_64-linux = "x64"; armv7l-linux = "arm"; aarch64-linux = "arm64"; }.${stdenv.hostPlatform.system};
  } // customGnFlags;

  common = { version }:
    let
      deps = import (./vendor- + version + ".nix") { inherit fetchgit fetchurl runCommand; };
      src = stdenvNoCC.mkDerivation rec {
        name = "chromium-${version}-src";
        buildCommand =
          # <nixpkgs/pkgs/build-support/trivial-builders.nix>'s `linkFarm` or `buiildEnv` would work here if they supported nested paths
          lib.concatStringsSep "\n" (
            lib.mapAttrsToList (path: src: ''
                                  echo mkdir -p $(dirname "$out/${path}")
                                       mkdir -p $(dirname "$out/${path}")
                                  echo cp -r "${src}" "$out/${path}"
                                       cp -r "${src}" "$out/${path}"
                                       chmod -R u+w "$out/${path}"
                                '') deps
          ) +
          # introduce files missing in git repos
          ''
            echo 'LASTCHANGE=${deps."src".rev}-refs/heads/master@{#0}'             > $out/src/build/util/LASTCHANGE
            echo '1555555555'                                                      > $out/src/build/util/LASTCHANGE.committime

            echo '/* Generated by lastchange.py, do not edit.*/'                   > $out/src/gpu/config/gpu_lists_version.h
            echo '#ifndef GPU_CONFIG_GPU_LISTS_VERSION_H_'                        >> $out/src/gpu/config/gpu_lists_version.h
            echo '#define GPU_CONFIG_GPU_LISTS_VERSION_H_'                        >> $out/src/gpu/config/gpu_lists_version.h
            echo '#define GPU_LISTS_VERSION "${deps."src".rev}"'                  >> $out/src/gpu/config/gpu_lists_version.h
            echo '#endif  // GPU_CONFIG_GPU_LISTS_VERSION_H_'                     >> $out/src/gpu/config/gpu_lists_version.h

            echo '/* Generated by lastchange.py, do not edit.*/'                   > $out/src/skia/ext/skia_commit_hash.h
            echo '#ifndef SKIA_EXT_SKIA_COMMIT_HASH_H_'                           >> $out/src/skia/ext/skia_commit_hash.h
            echo '#define SKIA_EXT_SKIA_COMMIT_HASH_H_'                           >> $out/src/skia/ext/skia_commit_hash.h
            echo '#define SKIA_COMMIT_HASH "${deps."src/third_party/skia".rev}-"' >> $out/src/skia/ext/skia_commit_hash.h
            echo '#endif  // SKIA_EXT_SKIA_COMMIT_HASH_H_'                        >> $out/src/skia/ext/skia_commit_hash.h
          '';
      };
    in stdenv.mkDerivation rec {
      pname = "chromium-git";
      inherit version src;

      nativeBuildInputs = [ gn ninja python2 pkg-config jre8 gperf bison ];
      buildInputs = [
        dbus at-spi2-atk atk at-spi2-core nspr nss pciutils utillinux kerberos
        gdk-pixbuf glib gtk3 alsaLib libXScrnSaver libXcursor libXtst libGLU_combined libXdamage
      ] ++ lib.optionals gnFlags.use_pulseaudio [
        pulseaudio
      ];

      postPatch = ''
        ( cd src
          # We want to be able to specify where the sandbox is via CHROME_DEVEL_SANDBOX
          substituteInPlace sandbox/linux/suid/client/setuid_sandbox_host.cc \
            --replace \
              'return sandbox_binary;' \
              'return base::FilePath(GetDevelSandboxPath());'

          substituteInPlace services/audio/audio_sandbox_hook_linux.cc \
            --replace \
              '/usr/share/alsa/' \
              '${alsaLib}/share/alsa/' \
            --replace \
              '/usr/lib/x86_64-linux-gnu/gconv/' \
              '${glibc}/lib/gconv/' \
            --replace \
              '/usr/share/locale/' \
              '${glibc}/share/locale/'

          sed -i -e 's@"\(#!\)\?.*xdg-@"\1${xdg_utils}/bin/xdg-@' \
            chrome/browser/shell_integration_linux.cc

          sed -i -e '/lib_loader.*Load/s!"\(libudev\.so\)!"${systemd.lib}/lib/\1!' \
            device/udev_linux/udev?_loader.cc

          sed -i -e '/libpci_loader.*Load/s!"\(libpci\.so\)!"${pciutils}/lib/\1!' \
            gpu/config/gpu_info_collector_linux.cc

          # Allow to put extensions into the system-path.
          sed -i -e 's,/usr,/run/current-system/sw,' chrome/common/chrome_paths.cc

          ${lib.optionalString stdenv.isAarch64 ''
              substituteInPlace build/toolchain/linux/BUILD.gn \
                --replace 'toolprefix = "aarch64-linux-gnu-"' 'toolprefix = ""'
           ''}

          patchShebangs --build .

          mkdir -p third_party/node/linux/node-linux-x64/bin
          ln -s ${nodejs}/bin/node                    third_party/node/linux/node-linux-x64/bin/node      || true

          mkdir -p third_party/llvm-build/Release+Asserts/bin
          ln -s ${llvmPackages_9.clang}/bin/clang     third_party/llvm-build/Release+Asserts/bin/clang    || true
          ln -s ${llvmPackages_9.clang}/bin/clang++   third_party/llvm-build/Release+Asserts/bin/clang++  || true
          ln -s ${llvmPackages_9.llvm}/bin/llvm-ar    third_party/llvm-build/Release+Asserts/bin/llvm-ar  || true

          echo 'build_with_chromium = true'                > build/config/gclient_args.gni
          echo 'checkout_android = false'                 >> build/config/gclient_args.gni
          echo 'checkout_android_native_support = false'  >> build/config/gclient_args.gni
          echo 'checkout_nacl = false'                    >> build/config/gclient_args.gni
          echo 'checkout_openxr = false'                  >> build/config/gclient_args.gni
          echo 'checkout_oculus_sdk = false'              >> build/config/gclient_args.gni
        )
      '';

      configurePhase = ''
        # attept to fix python2 failing with "EOFError: EOF read where object expected" on multi-core builders
        export PYTHONDONTWRITEBYTECODE=true
        ( cd src
          gn gen ${lib.escapeShellArg "--args=${gnToString gnFlags}"} out/Release
        )
      '';

      buildPhase = ''
        ( cd src
          ninja -C out/Release chrome

          find chrome/test/chromedriver -exec touch -t 198001010000.00 {} +   # fix zip issues with timestamps older than 1980
          ninja -C out/Release chromedriver
        )
      '';

      installPhase = ''
        ( cd src/out/Release
          mkdir -p locales resources extensions   # the directories are optional, ensure they exist for following `cp` success

          mkdir -p $out/bin
          cp -r chrome chromedriver locales resources extensions *.so *.pak *.dat *.bin $out/bin/
          ln -s -f $out/bin/chrome       $out/bin/chrome-${version}
          ln -s -f $out/bin/chromedriver $out/bin/chromedriver-${version}
        )
      '';

      meta = with stdenv.lib; {
        description = "An open source web browser from Google";
        homepage = https://github.com/chromium/chromium;
        license = licenses.bsd3;
        hydraPlatforms = [];
        platforms = [ "i686-linux" "armv7l-linux" "x86_64-linux" "aarch64-linux" ];
        maintainers = with maintainers; [ volth ];
      };
    };

in {
  chromium-git_78 = common { version = "78.0.3904.77";  };
  chromium-git_79 = common { version = "79.0.3945.9";   };
  chromium-git_80 = common { version = "80.0.3949.1";   };
}
