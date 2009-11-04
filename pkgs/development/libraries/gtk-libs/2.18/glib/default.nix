args: with args;

stdenv.mkDerivation rec {
  name = "glib-2.22.2";

  src = fetchurl {
    url = "mirror://gnome/sources/glib/2.22/${name}.tar.bz2";
    sha256 = "18ycpaf69wlpp4wq385hkq7bcfhbis8ncd7wl7zmwgrdzh11v954";
  };

  buildInputs = [pkgconfig gettext perl];

  # The nbd package depends on a static version of this library; hence
  # the default configure flag --disable-static is switched off.
  dontDisableStatic = true;
  configureFlags = "--enable-static --enable-shared";

  meta = {
    description = "GLib, a C library of programming buildings blocks";

    longDescription = ''
      GLib provides the core application building blocks for libraries
      and applications written in C.  It provides the core object
      system used in GNOME, the main loop implementation, and a large
      set of utility functions for strings and common data structures.
    '';

    homepage = http://www.gtk.org/;

    license = "LGPLv2+";

    maintainers = [stdenv.lib.maintainers.raskin];
    platforms = stdenv.lib.platforms.linux;
  };
}
