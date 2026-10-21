/*
 * Vérifie le contrat que Kodi 21.3 (CDVDVideoCodecDRMPRIME::FindHWConfig)
 * attend d'FFmpeg pour activer le décodage stateless V4L2 Request :
 *
 *   pix_fmt      == AV_PIX_FMT_DRM_PRIME
 *   methods      &  AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX
 *   device_type  == AV_HWDEVICE_TYPE_DRM
 *
 * Kodi 21.3 exige device_type == DRM (contrairement à master, détendu par
 * xbmc#25467) : c'est pourquoi le jeu LibreELEC 6.0/6.1 est utilisable tel
 * quel, sans type AV_HWDEVICE_TYPE_V4L2REQUEST.
 *
 * Sortie : une ligne par décodeur + le nom du décodeur retenu, sur stdout.
 * Code retour : 0 si h264 ET hevc exposent la config, 1 sinon.
 */
#include <libavcodec/avcodec.h>
#include <libavutil/pixdesc.h>

#include <stdio.h>

static int check_decoder(const char *name, enum AVCodecID id)
{
    const AVCodec *codec = avcodec_find_decoder(id);
    const AVCodecHWConfig *cfg;
    int n;

    if (!codec) {
        fprintf(stderr, "FAIL %s: décodeur absent de libavcodec\n", name);
        return 1;
    }

    for (n = 0; (cfg = avcodec_get_hw_config(codec, n)); n++) {
        if (cfg->pix_fmt != AV_PIX_FMT_DRM_PRIME)
            continue;
        if (!(cfg->methods & AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX))
            continue;
        if (cfg->device_type != AV_HWDEVICE_TYPE_DRM)
            continue;

        printf("OK %s: pix_fmt=%s methods=HW_DEVICE_CTX device_type=%s\n",
               name, av_get_pix_fmt_name(cfg->pix_fmt),
               av_hwdevice_get_type_name(cfg->device_type));
        return 0;
    }

    fprintf(stderr,
            "FAIL %s: aucune hw config DRM_PRIME/HW_DEVICE_CTX/DRM "
            "(%d config(s) vue(s))\n", name, n);
    return 1;
}

int main(void)
{
    int rc = 0;

    rc |= check_decoder("h264", AV_CODEC_ID_H264);
    rc |= check_decoder("hevc", AV_CODEC_ID_HEVC);

    return rc;
}
