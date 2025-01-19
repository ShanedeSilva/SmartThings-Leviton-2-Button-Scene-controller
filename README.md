# SmartThings Edge Driver for Leviton VRCS2-MRZ (Beta)

Edge Driver implements the Leviton VRCS2 device as a group of 2 on/off switches controlled by corresponding buttons on the VRCS2 device. Using SmartThings allows you to configure routines to integrate each switch to control other SmartThings devices.
The VRCS2 is an older device and discontinued by Leviton. 
* Dashboard displays the state of Switch 1.

## Fingerprints

```
  - id: "Leviton ZRCS2"
    deviceLabel: Leviton 2 Button Switch
    manufacturerId: 0x001D
    productType: 0x1000
    productId: 0x0261


  - id: "Leviton ZRCS2-MRZ"
    deviceLabel: Leviton 2 Button Switch
    genericType: 0x01
    specificType:
      - 0x00
    commandClasses:
      supported:
        - 0x2D
```


## To install

* Use the channel link (https://callaway.smartthings.com/channels/1a8f2b01-6fe5-4957-9601-9fa0267c6d8b) to enroll install the driver on your hub.
* Use the SmartThings app to exclude your device (there is currently no way to switch from a Groovy DTH to an Edge driver except by deleting and then adding the device).
* Use Add device → Scan nearby in the SmartThings app to include your device. Your device should pick up this driver if the fingerprint matches.

## Code

github.com: 
https://github.com/ShanedeSilva/SmartThings-Leviton-2-Button-Scene-controller

## Acknowledgments

* Brian Dalhem (@bdahlem) for the original DTH groovy code.
* Jason Brown (@j9brown) for documenting Leviton proprietary command for LED control.
* The SmartThings community (@jdroberts, @h0ckeysk8er, @philh30, @harobiunson) 

