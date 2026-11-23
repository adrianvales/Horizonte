import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;

module Sun {
    // Posición del sol. t = segundos UNIX (UTC). Devuelve [azimut, altura aparente] en grados.
    function pos(t, lat, lon) {
        var d = (t - 946728000).toDouble() / 86400.0d;
        var r = 0.017453292519943295d;
        var g = (357.529d + 0.98560028d * d) * r;
        var q = 280.459d + 0.98564736d * d;
        var L = (q + 1.915d * Math.sin(g) + 0.020d * Math.sin(2.0d * g)) * r;
        var e = (23.439d - 0.00000036d * d) * r;
        var ra = Math.atan2(Math.cos(e) * Math.sin(L), Math.cos(L));
        var dec = Math.asin(Math.sin(e) * Math.sin(L));
        var gmst = 18.697374558d + 24.06570982441908d * d;
        gmst = gmst - 24.0d * Math.floor(gmst / 24.0d);
        var H = (gmst * 15.0d + lon.toDouble()) * r - ra;
        var la = lat.toDouble() * r;
        var alt = Math.asin(Math.sin(la) * Math.sin(dec) + Math.cos(la) * Math.cos(dec) * Math.cos(H));
        var az = Math.atan2(-Math.sin(H), Math.tan(dec) * Math.cos(la) - Math.sin(la) * Math.cos(H));
        var altD = (alt / r).toFloat();
        if (altD > -1.0) {
            // refracción atmosférica (Bennett)
            altD += (1.02 / Math.tan((altD + 10.3 / (altD + 5.11)) * Geo.D2R)) / 60.0;
        }
        return [Geo.norm360((az / r).toFloat()), altD];
    }

    function hhmm(t) {
        var info = Gregorian.info(new Time.Moment(t), Time.FORMAT_SHORT);
        return info.hour.format("%02d") + ":" + info.min.format("%02d");
    }
}
