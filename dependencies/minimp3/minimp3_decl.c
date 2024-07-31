#define MINIMP3_NO_STDIO
#define MINIMP3_ONLY_MP3
#define MINIMP3_ALLOW_MONO_STEREO_TRANSITION
#define MINIMP3_IMPLEMENTATION
#include "minimp3_ex.h"

/*
static void decode_file(const char *input_file_name, const unsigned char *buf_ref, int ref_size, FILE *file_out)
{
    mp3dec_t mp3d;
    int i, res = -1, data_bytes, total_samples = 0, maxdiff = 0;
    int no_std_vec = strstr(input_file_name, "nonstandard") || strstr(input_file_name, "ILL");
    uint8_t *buf = 0;
    double MSE = 0.0, psnr;

    mp3dec_io_t io;
    mp3dec_file_info_t info;
    memset(&info, 0, sizeof(info));
    io.read = read_cb;
    io.seek = seek_cb;
        int size = 0;
        FILE *file = fopen(input_file_name, "rb");
        uint8_t *buf = preload(file, &size);
        fclose(file);
        res = buf ? mp3dec_load_buf(&mp3d, buf, size, &info, 0, 0) : MP3D_E_IOERROR;
        free(buf);
    if (res && MP3D_E_DECODE != res)
    {
        printf("error: read function failed, code=%d\n", res);
        exit(1);
    }
#ifdef MINIMP3_FLOAT_OUTPUT
    int16_t *buffer = malloc(info.samples*sizeof(int16_t));
    FAIL_MEM(buffer);
    mp3dec_f32_to_s16(info.buffer, buffer, info.samples);
    free(info.buffer);
#else
    int16_t *buffer = info.buffer;
#endif
#ifndef MINIMP3_NO_WAV
    if (wave_out && file_out)
        fwrite(wav_header(0, 0, 0, 0), 1, 44, file_out);
#endif
    total_samples += info.samples;
    if (buf_ref)
    {
        size_t ref_samples = ref_size/2;
        int len_match = ref_samples == info.samples;
        int relaxed_len_match = len_match || (ref_samples + 1152) == info.samples || (ref_samples + 2304) == info.samples;
        int seek_len_match = (ref_samples <= info.samples) || (ref_samples + 2304) >= info.samples;
        if ((((!relaxed_len_match && MODE_STREAM != mode && MODE_STREAM_BUF != mode && MODE_STREAM_CB != mode) || !seek_len_match) && (3 == info.layer || 0 == info.layer) && !no_std_vec) || (no_std_vec && !len_match))
        {   // some standard vectors are for some reason a little shorter
            printf("error: reference and produced number of samples do not match (%d/%d)\n", (int)ref_samples, (int)info.samples);
            exit(1);
        }
        int max_samples = MINIMP3_MIN(ref_samples, info.samples);
        for (i = 0; i < max_samples; i++)
        {
            int MSEtemp = abs((int)buffer[i] - (int)(int16_t)read16le(&buf_ref[i*sizeof(int16_t)]));
            if (MSEtemp > maxdiff)
                maxdiff = MSEtemp;
            MSE += (float)MSEtemp*(float)MSEtemp;
        }
    }
    if (file_out)
        fwrite(buffer, info.samples, sizeof(int16_t), file_out);
    if (buffer)
        free(buffer);

#ifndef LIBFUZZER
    MSE /= total_samples ? total_samples : 1;
    if (0 == MSE)
        psnr = 99.0;
    else
        psnr = 10.0*log10(((double)0x7fff*0x7fff)/MSE);
    printf("rate=%d samples=%d max_diff=%d PSNR=%f\n", info.hz, total_samples, maxdiff, psnr);
    if (psnr < 96)
    {
        printf("error: PSNR compliance failed\n");
        exit(1);
    }
#endif
#ifndef MINIMP3_NO_WAV
    if (wave_out && file_out)
    {
        data_bytes = ftell(file_out) - 44;
        rewind(file_out);
        fwrite(wav_header(info.hz, info.channels, 16, data_bytes), 1, 44, file_out);
    }
#endif
}
*/

/*
int mp3dec_load_cb(mp3dec_t *dec, mp3dec_io_t *io, uint8_t *buf, size_t buf_size, mp3dec_file_info_t *info, MP3D_PROGRESS_CB progress_cb, void *user_data)
{
    if (!dec || !buf || !info || (size_t)-1 == buf_size || (io && buf_size < MINIMP3_BUF_SIZE))
        return MP3D_E_PARAM;
    uint64_t detected_samples = 0;
    size_t orig_buf_size = buf_size;
    int to_skip = 0;
    mp3dec_frame_info_t frame_info;
    memset(info, 0, sizeof(*info));
    memset(&frame_info, 0, sizeof(frame_info));
    // skip id3 
    size_t filled = 0, consumed = 0;
    int eof = 0, ret = 0;
    if (io)
    {
        if (io->seek(0, io->seek_data))
            return MP3D_E_IOERROR;
        filled = io->read(buf, MINIMP3_ID3_DETECT_SIZE, io->read_data);
        if (filled > MINIMP3_ID3_DETECT_SIZE)
            return MP3D_E_IOERROR;
        if (MINIMP3_ID3_DETECT_SIZE != filled)
            return 0;
        size_t id3v2size = mp3dec_skip_id3v2(buf, filled);
        if (id3v2size)
        {
            if (io->seek(id3v2size, io->seek_data))
                return MP3D_E_IOERROR;
            filled = io->read(buf, buf_size, io->read_data);
            if (filled > buf_size)
                return MP3D_E_IOERROR;
        } else
        {
            size_t readed = io->read(buf + MINIMP3_ID3_DETECT_SIZE, buf_size - MINIMP3_ID3_DETECT_SIZE, io->read_data);
            if (readed > (buf_size - MINIMP3_ID3_DETECT_SIZE))
                return MP3D_E_IOERROR;
            filled += readed;
        }
        if (filled < MINIMP3_BUF_SIZE)
            mp3dec_skip_id3v1(buf, &filled);
    } else
    {
        mp3dec_skip_id3((const uint8_t **)&buf, &buf_size);
        if (!buf_size)
            return 0;
    }
    // try to make allocation size assumption by first frame or vbr tag 
    mp3dec_init(dec);
    int samples;
    do
    {
        uint32_t frames;
        int i, delay, padding, free_format_bytes = 0, frame_size = 0;
        const uint8_t *hdr;
        if (io)
        {
            if (!eof && filled - consumed < MINIMP3_BUF_SIZE)
            {   // keep minimum 10 consecutive mp3 frames (~16KB) worst case 
                memmove(buf, buf + consumed, filled - consumed);
                filled -= consumed;
                consumed = 0;
                size_t readed = io->read(buf + filled, buf_size - filled, io->read_data);
                if (readed > (buf_size - filled))
                    return MP3D_E_IOERROR;
                if (readed != (buf_size - filled))
                    eof = 1;
                filled += readed;
                if (eof)
                    mp3dec_skip_id3v1(buf, &filled);
            }
            i = mp3d_find_frame(buf + consumed, filled - consumed, &free_format_bytes, &frame_size);
            consumed += i;
            hdr = buf + consumed;
        } else
        {
            i = mp3d_find_frame(buf, buf_size, &free_format_bytes, &frame_size);
            buf      += i;
            buf_size -= i;
            hdr = buf;
        }
        if (i && !frame_size)
            continue;
        if (!frame_size)
            return 0;
        frame_info.channels = HDR_IS_MONO(hdr) ? 1 : 2;
        frame_info.hz = hdr_sample_rate_hz(hdr);
        frame_info.layer = 4 - HDR_GET_LAYER(hdr);
        frame_info.bitrate_kbps = hdr_bitrate_kbps(hdr);
        frame_info.frame_bytes = frame_size;
        samples = hdr_frame_samples(hdr)*frame_info.channels;
        if (3 != frame_info.layer)
            break;
        int ret = mp3dec_check_vbrtag(hdr, frame_size, &frames, &delay, &padding);
        if (ret > 0)
        {
            padding *= frame_info.channels;
            to_skip = delay*frame_info.channels;
            detected_samples = samples*(uint64_t)frames;
            if (detected_samples >= (uint64_t)to_skip)
                detected_samples -= to_skip;
            if (padding > 0 && detected_samples >= (uint64_t)padding)
                detected_samples -= padding;
            if (!detected_samples)
                return 0;
        }
        if (ret)
        {
            if (io)
            {
                consumed += frame_size;
            } else
            {
                buf      += frame_size;
                buf_size -= frame_size;
            }
        }
        break;
    } while(1);
    size_t allocated = MINIMP3_MAX_SAMPLES_PER_FRAME*sizeof(mp3d_sample_t);
    if (detected_samples)
        allocated += detected_samples*sizeof(mp3d_sample_t);
    else
        allocated += (buf_size/frame_info.frame_bytes)*samples*sizeof(mp3d_sample_t);
    info->buffer = (mp3d_sample_t*)malloc(allocated);
    if (!info->buffer)
        return MP3D_E_MEMORY;
    // save info 
    info->channels = frame_info.channels;
    info->hz       = frame_info.hz;
    info->layer    = frame_info.layer;
    // decode all frames 
    size_t avg_bitrate_kbps = 0, frames = 0;
    do
    {
        if ((allocated - info->samples*sizeof(mp3d_sample_t)) < MINIMP3_MAX_SAMPLES_PER_FRAME*sizeof(mp3d_sample_t))
        {
            allocated *= 2;
            mp3d_sample_t *alloc_buf = (mp3d_sample_t*)realloc(info->buffer, allocated);
            if (!alloc_buf)
                return MP3D_E_MEMORY;
            info->buffer = alloc_buf;
        }
        if (io)
        {
            if (!eof && filled - consumed < MINIMP3_BUF_SIZE)
            {   // keep minimum 10 consecutive mp3 frames (~16KB) worst case 
                memmove(buf, buf + consumed, filled - consumed);
                filled -= consumed;
                consumed = 0;
                size_t readed = io->read(buf + filled, buf_size - filled, io->read_data);
                if (readed != (buf_size - filled))
                    eof = 1;
                filled += readed;
                if (eof)
                    mp3dec_skip_id3v1(buf, &filled);
            }
            samples = mp3dec_decode_frame(dec, buf + consumed, filled - consumed, info->buffer + info->samples, &frame_info);
            consumed += frame_info.frame_bytes;
        } else
        {
            samples = mp3dec_decode_frame(dec, buf, MINIMP3_MIN(buf_size, (size_t)INT_MAX), info->buffer + info->samples, &frame_info);
            buf      += frame_info.frame_bytes;
            buf_size -= frame_info.frame_bytes;
        }
        if (samples)
        {
            if (info->hz != frame_info.hz || info->layer != frame_info.layer)
            {
                ret = MP3D_E_DECODE;
                break;
            }
            if (info->channels && info->channels != frame_info.channels)
            {
#ifdef MINIMP3_ALLOW_MONO_STEREO_TRANSITION
                info->channels = 0; // mark file with mono-stereo transition 
#else
                ret = MP3D_E_DECODE;
                break;
#endif
            }
            samples *= frame_info.channels;
            if (to_skip)
            {
                size_t skip = MINIMP3_MIN(samples, to_skip);
                to_skip -= skip;
                samples -= skip;
                memmove(info->buffer, info->buffer + skip, samples*sizeof(mp3d_sample_t));
            }
            info->samples += samples;
            avg_bitrate_kbps += frame_info.bitrate_kbps;
            frames++;
            if (progress_cb)
            {
                ret = progress_cb(user_data, orig_buf_size, orig_buf_size - buf_size, &frame_info);
                if (ret)
                    break;
            }
        }
    } while (frame_info.frame_bytes);
    if (detected_samples && info->samples > detected_samples)
        info->samples = detected_samples; // cut padding 
    // reallocate to normal buffer size 
    if (allocated != info->samples*sizeof(mp3d_sample_t))
    {
        mp3d_sample_t *alloc_buf = (mp3d_sample_t*)realloc(info->buffer, info->samples*sizeof(mp3d_sample_t));
        if (!alloc_buf && info->samples)
            return MP3D_E_MEMORY;
        info->buffer = alloc_buf;
    }
    if (frames)
        info->avg_bitrate_kbps = avg_bitrate_kbps/frames;
    return ret;
}
*/
