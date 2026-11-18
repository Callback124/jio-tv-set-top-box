package com.example.data.local

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "jiotv_guide_prefs")

data class UserPreferences(
    val favoriteChannelIds: Set<Int> = emptySet(),
    val reminderKeys: Set<String> = emptySet(),
    val selectedCategoryId: Int = 0,
    val selectedLanguageId: Int = 0,
    val hdOnly: Boolean = false,
    val playableOnly: Boolean = false,
    val darkTheme: Boolean = true,
    val customApiBaseUrl: String = ""
)

class PreferencesRepository(private val context: Context) {
    private object Keys {
        val FAVORITES = stringSetPreferencesKey("favorite_channel_ids")
        val REMINDERS = stringSetPreferencesKey("program_reminder_keys")
        val CATEGORY_ID = intPreferencesKey("selected_category_id")
        val LANGUAGE_ID = intPreferencesKey("selected_language_id")
        val HD_ONLY = booleanPreferencesKey("hd_only")
        val PLAYABLE_ONLY = booleanPreferencesKey("playable_only")
        val DARK_THEME = booleanPreferencesKey("dark_theme")
        val CUSTOM_BASE_URL = stringPreferencesKey("custom_api_base_url")
    }

    val preferencesFlow: Flow<UserPreferences> = context.dataStore.data.map { prefs ->
        UserPreferences(
            favoriteChannelIds = prefs[Keys.FAVORITES]?.mapNotNull { it.toIntOrNull() }?.toSet() ?: emptySet(),
            reminderKeys = prefs[Keys.REMINDERS] ?: emptySet(),
            selectedCategoryId = prefs[Keys.CATEGORY_ID] ?: 0,
            selectedLanguageId = prefs[Keys.LANGUAGE_ID] ?: 0,
            hdOnly = prefs[Keys.HD_ONLY] ?: false,
            playableOnly = prefs[Keys.PLAYABLE_ONLY] ?: false,
            darkTheme = prefs[Keys.DARK_THEME] ?: true,
            customApiBaseUrl = prefs[Keys.CUSTOM_BASE_URL] ?: ""
        )
    }

    suspend fun toggleFavorite(channelId: Int) {
        context.dataStore.edit { prefs ->
            val current = prefs[Keys.FAVORITES] ?: emptySet()
            val idStr = channelId.toString()
            prefs[Keys.FAVORITES] = if (idStr in current) current - idStr else current + idStr
        }
    }

    suspend fun toggleReminder(reminderKey: String) {
        context.dataStore.edit { prefs ->
            val current = prefs[Keys.REMINDERS] ?: emptySet()
            prefs[Keys.REMINDERS] = if (reminderKey in current) current - reminderKey else current + reminderKey
        }
    }

    suspend fun setCategory(categoryId: Int) {
        context.dataStore.edit { prefs -> prefs[Keys.CATEGORY_ID] = categoryId }
    }

    suspend fun setLanguage(languageId: Int) {
        context.dataStore.edit { prefs -> prefs[Keys.LANGUAGE_ID] = languageId }
    }

    suspend fun setHdOnly(hdOnly: Boolean) {
        context.dataStore.edit { prefs -> prefs[Keys.HD_ONLY] = hdOnly }
    }

    suspend fun setPlayableOnly(playableOnly: Boolean) {
        context.dataStore.edit { prefs -> prefs[Keys.PLAYABLE_ONLY] = playableOnly }
    }

    suspend fun setDarkTheme(darkTheme: Boolean) {
        context.dataStore.edit { prefs -> prefs[Keys.DARK_THEME] = darkTheme }
    }

    suspend fun setCustomApiBaseUrl(url: String) {
        context.dataStore.edit { prefs -> prefs[Keys.CUSTOM_BASE_URL] = url.trim().trimEnd('/') }
    }
}
