package com.polri.bodyworn.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class LocationSnapshotProvider(
    private val context: Context
) {
    @SuppressLint("MissingPermission")
    suspend fun getCurrentLocation(): Location? = withContext(Dispatchers.IO) {
        val hasFine = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val hasCoarse = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasFine && !hasCoarse) return@withContext null

        val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return@withContext null

        val providers = buildList {
            if (manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) add(LocationManager.GPS_PROVIDER)
            if (manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) add(LocationManager.NETWORK_PROVIDER)
            if (manager.isProviderEnabled(LocationManager.PASSIVE_PROVIDER)) add(LocationManager.PASSIVE_PROVIDER)
        }

        providers
            .mapNotNull(manager::getLastKnownLocation)
            .maxByOrNull(Location::getTime)
    }
}
