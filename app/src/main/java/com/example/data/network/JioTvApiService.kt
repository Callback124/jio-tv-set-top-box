package com.example.data.network

import com.example.data.model.ChannelListResponse
import okhttp3.OkHttpClient
import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import retrofit2.http.GET
import retrofit2.http.HeaderMap
import retrofit2.http.Query
import retrofit2.http.Streaming
import retrofit2.http.Url
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import java.util.concurrent.TimeUnit

interface JioTvApiService {
    @GET
    suspend fun fetchRawUrl(
        @Url url: String,
        @HeaderMap headers: Map<String, String>
    ): Response<ResponseBody>

    @Streaming
    @GET
    suspend fun probeStream(
        @Url url: String,
        @HeaderMap headers: Map<String, String>
    ): Response<ResponseBody>

    @GET
    suspend fun fetchChannelList(
        @Url url: String,
        @Query("os") os: String = "android",
        @Query("devicetype") deviceType: String = "phone",
        @Query("usertype") userType: String = "tvYR7NSNn7rymo3F",
        @HeaderMap headers: Map<String, String>
    ): Response<ChannelListResponse>

    @GET
    suspend fun fetchEpg(
        @Url url: String,
        @Query("offset") offset: Int,
        @Query("channel_id") channelId: Int,
        @Query("langId") langId: Int = 6,
        @HeaderMap headers: Map<String, String>
    ): Response<ResponseBody>
}

object JioTvNetworkModule {
    const val WEB_TV_GUIDE_URL = "https://www.jiotv.com/tv-guide"
    const val CHANNEL_LIST_V3_1 = "https://jiotv.data.cdn.jio.com/apis/v3.1/getMobileChannelList/get/"
    const val CHANNEL_LIST_V3_0 = "https://jiotv.data.cdn.jio.com/apis/v3.0/getMobileChannelList/get/"
    const val EPG_V1_3 = "https://jiotv.data.cdn.jio.com/apis/v1.3/getepg/get"
    const val DICTIONARY_V1_3 = "https://jiotv.data.cdn.jio.com/apis/v1.3/dictionary/get"
    const val EXTRA_PLAY_CHANNELS_URL = "https://api.npoint.io/9db02feba76eb297fc65?v=1794981838621"
    const val STREAM_PLAY_WORKER_URL = "https://eliteapiyash.streamxlive.workers.dev"
    const val JIO_API_KEY = "l7xx75e822925f184370b2e25170c5d5820a"

    const val MOBILE_CHROME_USER_AGENT =
        "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36"

    fun streamWorkerHeaders(): Map<String, String> = mapOf(
        "User-Agent" to MOBILE_CHROME_USER_AGENT,
        "Accept" to "application/json"
    )

    fun webHeaders(): Map<String, String> = mapOf(
        "User-Agent" to "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36",
        "Accept" to "text/html,application/xhtml+xml,application/xml;q=0.9,application/json,*/*;q=0.8",
        "Accept-Language" to "en-IN,en;q=0.9,hi;q=0.8"
    )

    fun cdnApiHeaders(): Map<String, String> = mapOf(
        "User-Agent" to "JioTV",
        "x-api-key" to JIO_API_KEY,
        "Origin" to "https://www.jiotv.com",
        "Referer" to "https://www.jiotv.com/tv-guide",
        "Accept" to "application/json",
        "appkey" to "NzNiMDhlYzQyNjJm",
        "os" to "android",
        "devicetype" to "phone"
    )

    fun createMoshi(): Moshi = Moshi.Builder()
        .addLast(KotlinJsonAdapterFactory())
        .build()

    fun createOkHttpClient(cacheDir: java.io.File? = null): OkHttpClient {
        val dispatcher = okhttp3.Dispatcher().apply {
            maxRequests = 40
            maxRequestsPerHost = 20
        }
        return OkHttpClient.Builder()
            .dispatcher(dispatcher)
            .connectionPool(okhttp3.ConnectionPool(16, 5, TimeUnit.MINUTES))
            .apply {
                if (cacheDir != null) {
                    cache(okhttp3.Cache(java.io.File(cacheDir, "jiotv_http_cache"), 25L * 1024L * 1024L))
                }
            }
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .writeTimeout(12, TimeUnit.SECONDS)
            .followRedirects(true)
            .build()
    }

    fun createApiService(
        okHttpClient: OkHttpClient = createOkHttpClient(),
        moshi: Moshi = createMoshi()
    ): JioTvApiService {
        return Retrofit.Builder()
            .baseUrl("https://jiotv.data.cdn.jio.com/")
            .client(okHttpClient)
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
            .create(JioTvApiService::class.java)
    }
}
