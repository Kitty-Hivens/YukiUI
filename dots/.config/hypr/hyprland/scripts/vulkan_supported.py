#!/usr/bin/env python3
"""Answer whether Vulkan can actually render on this machine.

Exit 0 when a Vulkan instance can be created AND at least one physical device
answers, non-zero otherwise. Nothing is printed.

Why not check for the driver package or an ICD manifest: a manifest is installed
by a driver package, and the package can be installed on hardware the driver does
not support (Mesa's ANV needs Intel Gen8, so an Ivy Bridge machine with
vulkan-intel present still enumerates no device). Why not vulkaninfo: that lives
in vulkan-tools, which is not installed on most machines, and a missing tool is
not the same answer as a missing driver.

So this asks the loader directly, through ctypes -- libvulkan.so.1 ships with the
loader every driver depends on, and its absence is itself the answer.
"""

import ctypes
import sys


class VkApplicationInfo(ctypes.Structure):
    _fields_ = [
        ("sType", ctypes.c_int),
        ("pNext", ctypes.c_void_p),
        ("pApplicationName", ctypes.c_char_p),
        ("applicationVersion", ctypes.c_uint32),
        ("pEngineName", ctypes.c_char_p),
        ("engineVersion", ctypes.c_uint32),
        ("apiVersion", ctypes.c_uint32),
    ]


class VkInstanceCreateInfo(ctypes.Structure):
    _fields_ = [
        ("sType", ctypes.c_int),
        ("pNext", ctypes.c_void_p),
        ("flags", ctypes.c_uint32),
        ("pApplicationInfo", ctypes.POINTER(VkApplicationInfo)),
        ("enabledLayerCount", ctypes.c_uint32),
        ("ppEnabledLayerNames", ctypes.c_void_p),
        ("enabledExtensionCount", ctypes.c_uint32),
        ("ppEnabledExtensionNames", ctypes.c_void_p),
    ]


STRUCTURE_TYPE_APPLICATION_INFO = 0
STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1
API_VERSION_1_0 = 1 << 22


def main() -> int:
    try:
        vulkan = ctypes.CDLL("libvulkan.so.1")
    except OSError:
        return 1

    app = VkApplicationInfo(
        sType=STRUCTURE_TYPE_APPLICATION_INFO,
        pNext=None,
        pApplicationName=b"yukiui-vulkan-probe",
        applicationVersion=0,
        pEngineName=b"yukiui",
        engineVersion=0,
        apiVersion=API_VERSION_1_0,
    )
    info = VkInstanceCreateInfo(
        sType=STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        pNext=None,
        flags=0,
        pApplicationInfo=ctypes.pointer(app),
        enabledLayerCount=0,
        ppEnabledLayerNames=None,
        enabledExtensionCount=0,
        ppEnabledExtensionNames=None,
    )

    instance = ctypes.c_void_p()
    if vulkan.vkCreateInstance(ctypes.byref(info), None, ctypes.byref(instance)) != 0:
        return 1

    try:
        count = ctypes.c_uint32(0)
        if vulkan.vkEnumeratePhysicalDevices(instance, ctypes.byref(count), None) != 0:
            return 1
        # A loader with no usable driver creates an instance happily and then
        # reports no devices, which is exactly the case this exists to catch.
        return 0 if count.value > 0 else 1
    finally:
        vulkan.vkDestroyInstance(instance, None)


if __name__ == "__main__":
    sys.exit(main())
