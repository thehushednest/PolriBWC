package com.polri.bodyworn.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface RecordingDao {
    @Query("SELECT * FROM recordings ORDER BY recordedAtEpochMillis DESC")
    fun observeAll(): Flow<List<Recording>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(recording: Recording)
}
