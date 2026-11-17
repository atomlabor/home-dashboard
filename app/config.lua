-- Install-time configuration (Project settings -> Install-time configuration).
-- Studio writes the values over the markers in the copy that goes onto the device.
return {
  url = "__APP_CONFIG_HA_URL__",
  token = "__APP_CONFIG_HA_TOKEN__",
  marks = { url = "__APP_CONFIG_" .. "HA_URL__", token = "__APP_CONFIG_" .. "HA_TOKEN__" },
}
