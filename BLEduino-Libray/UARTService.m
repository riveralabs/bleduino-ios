//
//  UARTServiceClass.m
//  BLEduino
//
//  Created by Ramon Gonzalez on 9/24/13.
//  Copyright (c) 2013 Kytelabs. All rights reserved.
//

#import "UARTService.h"

/****************************************************************************/
/*						Service & Characteristics							*/
/****************************************************************************/
NSString * const kUARTServiceUUIDString = @"8C6BDA7A-A312-681D-025B-0032C0D16A2D";
NSString * const kRxCharacteristicUUIDString = @"8C6BABCD-A312-681D-025B0032C0D16A2D";
NSString * const kTxCharacteristicUUIDString = @"8C6B1010-A312-681D-025B0032C0D16A2D";

@interface UARTService() <CBPeripheralDelegate>

@property (nonatomic, strong) CBPeripheral *servicePeripheral;

@property (nonatomic, strong) CBService *uartService;
@property (nonatomic, strong) CBCharacteristic *rxCharacteristic;
@property (nonatomic, strong) CBCharacteristic *txCharacteristic;

@property (nonatomic, strong) CBUUID *uartServiceUUID;
@property (nonatomic, strong) CBUUID *rxCharacteristicUUID;
@property (nonatomic, strong) CBUUID *txCharacteristicUUID;

@property (nonatomic, weak) id <UARTServiceDelegate> delegate;

@property (nonatomic) BOOL longTransmission;
@property (nonatomic) BOOL textTransmission;
@property (nonatomic) BOOL textSubscription;

@end


@implementation UARTService

#pragma mark -
#pragma mark Init
/****************************************************************************/
/*								Init										*/
/****************************************************************************/

- (id) initWithPeripheral:(CBPeripheral *)aPeripheral
               controller:(id<UARTServiceDelegate>)aController
{
    self = [super init];
    if (self) {
        _servicePeripheral = [aPeripheral copy];
        _servicePeripheral.delegate = self;
		_delegate = aController;
        
        _uartServiceUUID = [CBUUID UUIDWithString:kUARTServiceUUIDString];
        _rxCharacteristicUUID = [CBUUID UUIDWithString:kRxCharacteristicUUIDString];
        _txCharacteristicUUID = [CBUUID UUIDWithString:kTxCharacteristicUUIDString];
    }
    
    return self;
}

- (id) uartServiceWithController:(id<UARTServiceDelegate>)aController
{
    //PENDING
    //selects peripheral automatically and abstracts the need to handle the peripheral completely.
    return nil;
}


#pragma mark -
#pragma mark Write Messages
/****************************************************************************/
/*				      Write messages/data to BLEduino                       */
/****************************************************************************/

- (void) writeData:(NSData *)data withAck:(BOOL)enabled
{
    int dataLength = data.length;
    
    if(dataLength > 20)
    {
        BOOL lastPacket = false;
        int dataIndex = 0;
        int totalPackets = ceil(dataLength / 20);
        
        for (int packetIndex = 0; packetIndex <= totalPackets; packetIndex++)
        {
            lastPacket = (packetIndex == totalPackets);
            int rangeLength = (lastPacket)?(dataLength - dataIndex):20;
            
            NSRange dataRange = NSMakeRange(dataIndex, rangeLength);
            NSData *dataSubset = [data subdataWithRange:dataRange];
            self.longTransmission = lastPacket;
            
            if(enabled)
            {
                [self.servicePeripheral writeValue:dataSubset
                                 forCharacteristic:self.rxCharacteristic
                                              type:CBCharacteristicWriteWithResponse];
            }
            else
            {
                [self.servicePeripheral writeValue:dataSubset
                                 forCharacteristic:self.rxCharacteristic
                                              type:CBCharacteristicWriteWithoutResponse];
            }
            
            //Move dataIndex to the start of next packet.
            dataIndex += 20;
        }
    }
    else
    {
        if(enabled)
        {
            [self.servicePeripheral writeValue:data
                             forCharacteristic:self.rxCharacteristic
                                          type:CBCharacteristicWriteWithResponse];
        }
        else
        {
            [self.servicePeripheral writeValue:data
                             forCharacteristic:self.rxCharacteristic
                                          type:CBCharacteristicWriteWithoutResponse];
        }

    }
}

- (void) writeData:(NSData *)data
{
    [self writeData:data withAck:NO];
}

- (void) writeMessage:(NSString *)message withAck:(BOOL)enabled
{
    self.textTransmission = YES;
    
    NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
    [self writeData:messageData withAck:enabled];
}

- (void) writeMessage:(NSString *)message
{
    self.messageSent = message;
    [self writeMessage:message withAck:NO];
}


#pragma mark -
#pragma mark Read Messages
/****************************************************************************/
/*				      Read messages / data from BLEduino                    */
/****************************************************************************/

- (void) readData
{
    [self.servicePeripheral readValueForCharacteristic:self.txCharacteristic];
}

- (void)readMessage
{
    self.textTransmission = YES;
    [self readData];
}

- (void) subscribeToStartReceivingData
{
    [self.servicePeripheral setNotifyValue:YES forCharacteristic:self.txCharacteristic];
}

- (void) unsubscribeToStopReiceivingData
{
    [self.servicePeripheral setNotifyValue:NO forCharacteristic:self.txCharacteristic];
}

- (void) subscribeToStartReceivingMessages
{
    self.textSubscription = YES;
    [self subscribeToStartReceivingData];
}

- (void) unsubscribeToStopReiceivingMessages
{
    self.textSubscription = NO;
    [self unsubscribeToStopReiceivingData];
}

- (void) dismissPeripheral
{
	if (self.servicePeripheral) {
        self.servicePeripheral.delegate = nil;
		self.servicePeripheral = nil;
	}
}

#pragma mark -
#pragma mark Peripheral Delegate
/****************************************************************************/
/*				            Peripheral Delegate                             */
/****************************************************************************/

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if(!self.longTransmission)
    {
        if ([self.delegate respondsToSelector:@selector(uartService:didWriteMessage:error:)])
        {
            [self.delegate uartService:self didWriteMessage:self.messageSent error:error];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if(!self.longTransmission)
    {
        if ([self.delegate respondsToSelector:@selector(uartService:didReceiveMessage:error:)])
        {
            [self.delegate uartService:self didReceiveMessage:self.messageReceived error:error];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if(characteristic.isNotifying)
    {
        if(self.textSubscription)
        {
            if ([self.delegate respondsToSelector:@selector(didSubscribeToReceiveMessagesFor:error:)])
            {
                [self.delegate didSubscribeToReceiveMessagesFor:self error:error];
            }
            self.textSubscription = NO;
        }
        else
        {
            if ([self.delegate respondsToSelector:@selector(didSubscribeToReceiveDataFor:error:)])
            {
                [self.delegate didSubscribeToReceiveDataFor:self error:error];
            }
        }
    }
    else
    {
        if (self.textSubscription)
        {
            if ([self.delegate respondsToSelector:@selector(didUnsubscribeToReceiveMessagesFor:error:)])
            {
                [self.delegate didUnsubscribeToReceiveMessagesFor:self error:error];
            }
            self.textSubscription = NO;
        }
        else
        {
            if ([self.delegate respondsToSelector:@selector(didUnsubscribeToReceiveDataFor:error:)])
            {
                [self.delegate didSubscribeToReceiveDataFor:self error:error];
            }
        }
    }
}

@end
