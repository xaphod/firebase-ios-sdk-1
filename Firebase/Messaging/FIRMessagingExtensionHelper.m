/*
 * Copyright 2019 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <FirebaseMessaging/FIRMessagingExtensionHelper.h>

#import <GoogleDataTransport/GoogleDataTransport.h>

#import "Firebase/Messaging/FIRMMessageCode.h"
#import "Firebase/Messaging/FIRMessagingLogger.h"

static NSString *const kPayloadOptionsName = @"fcm_options";
static NSString *const kPayloadOptionsImageURLName = @"image";

@interface FIRMessagingLogMessage : NSObject {
    NSString *_message;
}
@end

@interface FIRMessagingLogMessage (GDTEventDataObject) <GDTCOREventDataObject>
@end

@implementation FIRMessagingLogMessage

- (NSData *)transportBytes {
  // The implementation of transportBytes can be as simple as calling -data on
  // a protobuf (GPBMessage) if you're using canonical protobuf.
  // Using nanopb
  return [_message dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)setMessage:(NSString *)message {
    _message = message;
}
@end

@interface FIRMessagingExtensionHelper ()
@property(nonatomic, strong) void (^contentHandler)(UNNotificationContent *contentToDeliver);
@property(nonatomic, strong) UNMutableNotificationContent *bestAttemptContent;

@end

@implementation FIRMessagingExtensionHelper

- (void)populateNotificationContent:(UNMutableNotificationContent *)content
                 withContentHandler:(void (^)(UNNotificationContent *_Nonnull))contentHandler {
    
  GDTCORTransport *transport =
  [[GDTCORTransport alloc] initWithMappingID:@"137"
                             transformers:nil
                                   target:kGDTCORTargetCCT];
  NSString *messageDelivery = @"FCM iOS Message Delivery";
  FIRMessagingLogMessage *foo = [[FIRMessagingLogMessage alloc] init];
  [foo setMessage:messageDelivery];
  
  // Do stuff setting the fields of someFoo.

  GDTCOREvent *event = [transport eventForTransport];
  event.dataObject = foo;

  // Use this API for SDK service data events.
  [transport sendDataEvent:event];

  // Use this API for SDK telemetry events.
  [transport sendTelemetryEvent:event];
    
    
  self.contentHandler = [contentHandler copy];
  self.bestAttemptContent = content;

  // The `userInfo` property isn't available on newer versions of tvOS.
#if TARGET_OS_IOS || TARGET_OS_OSX
  NSString *currentImageURL = content.userInfo[kPayloadOptionsName][kPayloadOptionsImageURLName];
  if (!currentImageURL) {
    [self deliverNotification];
    return;
  }
  NSURL *attachmentURL = [NSURL URLWithString:currentImageURL];
  if (attachmentURL) {
    [self loadAttachmentForURL:attachmentURL
             completionHandler:^(UNNotificationAttachment *attachment) {
               self.bestAttemptContent.attachments = @[ attachment ];
               [self deliverNotification];
             }];
  } else {
    FIRMessagingLoggerError(kFIRMessagingServiceExtensionImageInvalidURL,
                            @"The Image URL provided is invalid %@.", currentImageURL);
    [self deliverNotification];
  }
#else
  [self deliverNotification];
#endif
}

#if TARGET_OS_IOS || TARGET_OS_OSX
- (void)loadAttachmentForURL:(NSURL *)attachmentURL
           completionHandler:(void (^)(UNNotificationAttachment *))completionHandler {
  __block UNNotificationAttachment *attachment = nil;

   NSURLSession *session = [NSURLSession
      sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
  [[session
      downloadTaskWithURL:attachmentURL
        completionHandler:^(NSURL *temporaryFileLocation, NSURLResponse *response, NSError *error) {
          if (error != nil) {
            FIRMessagingLoggerError(kFIRMessagingServiceExtensionImageNotDownloaded,
                                    @"Failed to download image given URL %@, error: %@\n",
                                    attachmentURL, error);
            completionHandler(attachment);
            return;
          }

           NSFileManager *fileManager = [NSFileManager defaultManager];
          NSString *fileExtension =
              [NSString stringWithFormat:@".%@", [response.suggestedFilename pathExtension]];
          NSURL *localURL = [NSURL
              fileURLWithPath:[temporaryFileLocation.path stringByAppendingString:fileExtension]];
          [fileManager moveItemAtURL:temporaryFileLocation toURL:localURL error:&error];
          if (error) {
            FIRMessagingLoggerError(
                kFIRMessagingServiceExtensionLocalFileNotCreated,
                @"Failed to move the image file to local location: %@, error: %@\n", localURL,
                error);
            completionHandler(attachment);
            return;
          }

           attachment = [UNNotificationAttachment attachmentWithIdentifier:@""
                                                                      URL:localURL
                                                                  options:nil
                                                                    error:&error];
          if (error) {
            FIRMessagingLoggerError(kFIRMessagingServiceExtensionImageNotAttached,
                                    @"Failed to create attachment with URL %@, error: %@\n",
                                    localURL, error);
            completionHandler(attachment);
            return;
          }
          completionHandler(attachment);
        }] resume];
}
#endif

- (void)deliverNotification {
  if (self.contentHandler) {
    self.contentHandler(self.bestAttemptContent);
  }
}

 @end

