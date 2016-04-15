////////////////////////////////////////////////////////////////////////////
//
// Copyright 2016 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

#import "RLMTestCase.h"

@interface LinkingObjectsTests : RLMTestCase
@end

@implementation LinkingObjectsTests

- (void)testBasics {
    NSArray *(^asArray)(id) = ^(id arrayLike) {
        return [arrayLike valueForKeyPath:@"self"];
    };

    RLMRealm *realm = [self realmWithTestPath];
    [realm beginWriteTransaction];

    PersonObject *hannah = [PersonObject createInRealm:realm withValue:@[ @"Hannah", @0 ]];
    PersonObject *mark   = [PersonObject createInRealm:realm withValue:@[ @"Mark",  @30, @[ hannah ]]];

    RLMLinkingObjects *hannahsParents = hannah.parents;
    XCTAssertEqualObjects(asArray(hannahsParents), (@[ mark ]));

    [realm commitWriteTransaction];

    XCTAssertEqualObjects(asArray(hannahsParents), (@[ mark ]));

    [realm beginWriteTransaction];
    PersonObject *diane = [PersonObject createInRealm:realm withValue:@[ @"Diane", @29, @[ hannah ]]];
    [realm commitWriteTransaction];

    XCTAssertEqualObjects(asArray(hannahsParents), (@[ mark, diane ]));
}

- (void)testNotificationSentInitially {
    RLMRealm *realm = [self realmWithTestPath];
    [realm beginWriteTransaction];

    PersonObject *hannah = [PersonObject createInRealm:realm withValue:@[ @"Hannah", @0 ]];
    PersonObject *mark   = [PersonObject createInRealm:realm withValue:@[ @"Mark",  @30, @[ hannah ]]];

    [realm commitWriteTransaction];

    id expectation = [self expectationWithDescription:@""];
    RLMNotificationToken *token = [hannah.parents addNotificationBlock:^(RLMResults *linkingObjects, NSError *error) {
        XCTAssertEqualObjects([linkingObjects valueForKeyPath:@"self"], (@[ mark ]));
        XCTAssertNil(error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    [token stop];
}

- (void)testNotificationSentAfterCommit {
    RLMRealm *realm = self.realmWithTestPath;
    [realm beginWriteTransaction];
    PersonObject *hannah = [PersonObject createInRealm:realm withValue:@[ @"Hannah", @0 ]];
    [realm commitWriteTransaction];

    __block id expectation = [self expectationWithDescription:@""];
    RLMNotificationToken *token = [hannah.parents addNotificationBlock:^(RLMResults *linkingObjects, NSError *error) {
        XCTAssertNotNil(linkingObjects);
        XCTAssertNil(error);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    expectation = [self expectationWithDescription:@""];
    [self dispatchAsyncAndWait:^{
        RLMRealm *realm = self.realmWithTestPath;
        [realm transactionWithBlock:^{
            [PersonObject createInRealm:realm withValue:@[ @"Mark",  @30, [PersonObject objectsInRealm:realm where:@"name == 'Hannah'"] ]];
        }];
    }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    [token stop];
}

- (void)testNotificationNotSentForUnrelatedChange {
    RLMRealm *realm = self.realmWithTestPath;
    [realm beginWriteTransaction];
    PersonObject *hannah = [PersonObject createInRealm:realm withValue:@[ @"Hannah", @0 ]];
    [realm commitWriteTransaction];

    id expectation = [self expectationWithDescription:@""];
    RLMNotificationToken *token = [hannah.parents addNotificationBlock:^(__unused RLMResults *linkingObjects, __unused NSError *error) {
        // will throw if it's incorrectly called a second time due to the
        // unrelated write transaction
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    // All notification blocks are called as part of a single runloop event, so
    // waiting for this one also waits for the above one to get a chance to run
    [self waitForNotification:RLMRealmDidChangeNotification realm:realm block:^{
        [self dispatchAsyncAndWait:^{
            [self.realmWithTestPath transactionWithBlock:^{ }];
        }];
    }];
    [token stop];
}

- (void)testNotificationSentOnlyForActualRefresh {
    RLMRealm *realm = self.realmWithTestPath;
    [realm beginWriteTransaction];
    PersonObject *hannah = [PersonObject createInRealm:realm withValue:@[ @"Hannah", @0 ]];
    [realm commitWriteTransaction];

    __block id expectation = [self expectationWithDescription:@""];
    RLMNotificationToken *token = [hannah.parents addNotificationBlock:^(RLMResults *linkingObjects, NSError *error) {
        XCTAssertNotNil(linkingObjects);
        XCTAssertNil(error);
        // will throw if it's called a second time before we create the new
        // expectation object immediately before manually refreshing
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    // Turn off autorefresh, so the background commit should not result in a notification
    realm.autorefresh = NO;

    // All notification blocks are called as part of a single runloop event, so
    // waiting for this one also waits for the above one to get a chance to run
    [self waitForNotification:RLMRealmRefreshRequiredNotification realm:realm block:^{
        [self dispatchAsyncAndWait:^{
            RLMRealm *realm = self.realmWithTestPath;
            [realm transactionWithBlock:^{
                [PersonObject createInRealm:realm withValue:@[ @"Mark",  @30, [PersonObject objectsInRealm:realm where:@"name == 'Hannah'"] ]];
            }];
        }];
    }];

    expectation = [self expectationWithDescription:@""];
    [realm refresh];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    [token stop];
}

- (void)testDeletingObjectWithNotificationsRegistered {
    RLMRealm *realm = self.realmWithTestPath;
    [realm beginWriteTransaction];
    PersonObject *hannah = [PersonObject createInRealm:realm withValue:@[ @"Hannah", @0 ]];
    PersonObject *mark   = [PersonObject createInRealm:realm withValue:@[ @"Mark",  @30, @[ hannah ]]];
    [realm commitWriteTransaction];

    __block id expectation = [self expectationWithDescription:@""];
    RLMNotificationToken *token = [hannah.parents addNotificationBlock:^(RLMResults *linkingObjects, NSError *error) {
        XCTAssertNotNil(linkingObjects);
        XCTAssertNil(error);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];

    [realm beginWriteTransaction];
    [realm deleteObject:mark];
    [realm commitWriteTransaction];

    [token stop];
}

@end