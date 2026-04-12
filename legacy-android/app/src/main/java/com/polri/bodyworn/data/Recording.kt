package com.polri.bodyworn.data

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "recordings")
data class Recording(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val officerName: String,
    val unitName: String,
    val fileUri: String,
    val recordedAtEpochMillis: Long,
    val latitude: Double?,
    val longitude: Double?,
    val source: String,
    val notes: String
)
