//
//  OCNotesHelper.m
//  iOCNotes
//

/************************************************************************
 
 Copyright 2014 Peter Hedlund peter.hedlund@me.com
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 
 1. Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 *************************************************************************/

#import "OCNotesHelper.h"
#import "OCAPIClient.h"
#import "NSDictionary+HandleNull.h"

@interface OCNotesHelper () {
    NSMutableArray *notesToAdd;
    NSMutableArray *notesToDelete;
    NSMutableArray *notesToUpdate;
}

@end

@implementation OCNotesHelper

@synthesize context;
@synthesize objectModel;
@synthesize coordinator;
@synthesize noteRequest;

+ (OCNotesHelper*)sharedHelper {
    static dispatch_once_t once_token;
    static id sharedHelper;
    dispatch_once(&once_token, ^{
        sharedHelper = [[OCNotesHelper alloc] init];
    });
    return sharedHelper;
}

- (OCNotesHelper*)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    notesToAdd = [NSMutableArray new];
    notesToDelete = [NSMutableArray new];
    notesToUpdate = [NSMutableArray new];
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [notesToAdd addObjectsFromArray:[[prefs arrayForKey:@"NotesToAdd"] mutableCopy]];
    [notesToDelete addObjectsFromArray:[[prefs arrayForKey:@"NotesToDelete"] mutableCopy]];
    [notesToUpdate addObjectsFromArray:[[prefs arrayForKey:@"NotesToUpdate"] mutableCopy]];
    
    __unused BOOL reachable = [[OCAPIClient sharedClient] reachabilityManager].isReachable;
    
    return self;
}

- (NSManagedObjectModel *)objectModel {
    if (!objectModel) {
        NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Notes" withExtension:@"momd"];
        objectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    }
    return objectModel;
}

- (NSPersistentStoreCoordinator *)coordinator {
    if (!coordinator) {
    
        NSManagedObjectModel *mom = self.objectModel;
        if (!mom) {
            NSLog(@"%@:%@ No model to generate a store from", [self class], NSStringFromSelector(_cmd));
            return nil;
        }
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *applicationFilesDirectory = [self applicationFilesDirectory];
        NSError *error = nil;
        
        NSDictionary *properties = [applicationFilesDirectory resourceValuesForKeys:@[NSURLIsDirectoryKey] error:&error];
        
        if (!properties) {
            BOOL ok = NO;
            if ([error code] == NSFileReadNoSuchFileError) {
                ok = [fileManager createDirectoryAtPath:[applicationFilesDirectory path] withIntermediateDirectories:YES attributes:nil error:&error];
            }
            if (!ok) {
                [[NSApplication sharedApplication] presentError:error];
                return nil;
            }
        } else {
            if (![properties[NSURLIsDirectoryKey] boolValue]) {
                // Customize and localize this error.
                NSString *failureDescription = [NSString stringWithFormat:@"Expected a folder to store application data, found a file (%@).", [applicationFilesDirectory path]];
                
                NSMutableDictionary *dict = [NSMutableDictionary dictionary];
                [dict setValue:failureDescription forKey:NSLocalizedDescriptionKey];
                error = [NSError errorWithDomain:@"YOUR_ERROR_DOMAIN" code:101 userInfo:dict];
                
                [[NSApplication sharedApplication] presentError:error];
                return nil;
            }
        }
        
        NSURL *url = [applicationFilesDirectory URLByAppendingPathComponent:@"CloudNotes.storedata"];
        NSPersistentStoreCoordinator *myCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:mom];
        if (![myCoordinator addPersistentStoreWithType:NSXMLStoreType configuration:nil URL:url options:nil error:&error]) {
            [[NSApplication sharedApplication] presentError:error];
            return nil;
        }
        coordinator = myCoordinator;
    }
    return coordinator;
}

- (NSManagedObjectContext *)context {
    if (!context) {
        NSPersistentStoreCoordinator *myCoordinator = [self coordinator];
        if (myCoordinator != nil) {
            context = [[NSManagedObjectContext alloc] init];
            [context setPersistentStoreCoordinator:myCoordinator];
        }
    }
    return context;
}

// Returns the directory the application uses to store the Core Data store file. This code uses a directory named "com.peterandlinda.CloudNotes" in the user's Application Support directory.
- (NSURL *)applicationFilesDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *appSupportURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
    return [appSupportURL URLByAppendingPathComponent:@"com.peterandlinda.CloudNotes"];
}
- (void)saveContext {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:notesToAdd forKey:@"NotesToAdd"];
    [prefs setObject:notesToDelete forKey:@"NotesToDelete"];
    [prefs setObject:notesToUpdate forKey:@"NotesToUpdate"];
    [prefs synchronize];
    
    NSError *error = nil;
    if (self.context != nil) {
        if ([self.context hasChanges] && ![self.context save:&error]) {
            NSLog(@"Error saving data %@, %@", error, [error userInfo]);
            //abort();
        } else {
            NSLog(@"Data saved");
        }
    }
}

- (Note*)noteWithId:(NSNumber *)noteId {
    [self.noteRequest setPredicate:[NSPredicate predicateWithFormat:@"myId == %@", noteId]];
    NSArray *notes = [self.context executeFetchRequest:self.noteRequest error:nil];
    return (Note*)[notes firstObject];
}

/*
 Get all notes
 
 Status: Implemented
 Method: GET
 Route: /notes
 Parameters: none
 Returns:
 
 [
 {
 id: 76,
 modified: 1376753464,
 title: "New note"
 content: "New note\n and something more",
 }, // etc
 ]
 */
- (void) sync {
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        
        NSDictionary *params = @{@"exclude": @""};
        [[OCAPIClient sharedClient] GET:@"notes" parameters:params success:^(NSURLSessionDataTask *task, id responseObject) {
            
            NSArray *serverNotesDictArray = (NSArray *)responseObject;
            if (serverNotesDictArray) {
                NSArray *serverIds = [serverNotesDictArray valueForKey:@"id"];
                
                NSError *error = nil;
                [self.noteRequest setPredicate:nil];
                NSArray *knownLocalNotes = [self.context executeFetchRequest:self.noteRequest error:&error];
                NSArray *knownIds = [knownLocalNotes valueForKey:@"myId"];
                
                NSLog(@"Count: %lu", (unsigned long)knownLocalNotes.count);
                
                error = nil;
                
                NSMutableArray *newOnServer = [NSMutableArray arrayWithArray:serverIds];
                [newOnServer removeObjectsInArray:knownIds];
                NSLog(@"New on server: %@", newOnServer);
                [newOnServer enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    NSPredicate * predicate = [NSPredicate predicateWithFormat:@"id == %@", obj];
                    NSArray * matches = [serverNotesDictArray filteredArrayUsingPredicate:predicate];
                    if (matches.count > 0) {
                        if ([notesToDelete indexOfObject:obj] == NSNotFound) {
                            [self addNoteFromDictionary:[matches lastObject]];
                        }
                    }
                }];
                
                NSMutableArray *deletedOnServer = [NSMutableArray arrayWithArray:knownIds];
                [deletedOnServer removeObjectsInArray:serverIds];
                NSLog(@"Deleted on server: %@", deletedOnServer);
                while (deletedOnServer.count > 0) {
                    Note *noteToRemove = [self noteWithId:[deletedOnServer lastObject]];
                    [self.context deleteObject:noteToRemove];
                    [deletedOnServer removeLastObject];
                }
                
                [serverNotesDictArray enumerateObjectsUsingBlock:^(NSDictionary *noteDict, NSUInteger idx, BOOL *stop) {
                    Note *note = [self noteWithId:[noteDict objectForKey:@"id"]];
                    note.title = [noteDict objectForKey:@"title"];
                    note.content = [noteDict objectForKeyNotNull:@"content" fallback:@""];
                    note.modified = [noteDict objectForKey:@"modified"];
                    [self.context processPendingChanges]; //Prevents crashes
                }];
            }
            [self saveContext];
            [self deleteNotesFromServer:notesToDelete];
            [self addNotesToServer:notesToAdd];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkSuccess" object:self userInfo:nil];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            NSString *message = [NSString stringWithFormat:@"The server responded '%@' and the error reported was '%@'", [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode], [error localizedDescription]];
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Updating Notes", @"Title", message, @"Message", nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
        }];
    } else {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Unable to Reach Server", @"Title",
                                  @"Please check network connection and login.", @"Message", nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
    }
}

/*
 Get a note
 
 Status: Implemented
 Method: GET
 Route: /notes/{noteId}
 Parameters: none
 Return codes:
 HTTP 404: If the note does not exist
 Returns:
 
 {
 id: 76,
 modified: 1376753464,
 title: "New note"
 content: "New note\n and something more",
 }
 */

- (void)getNote:(Note *)note {
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        //online
        NSString *path = [NSString stringWithFormat:@"notes/%@", [note.myId stringValue]];
        __block Note *noteToGet = (Note*)[self.context objectWithID:note.objectID];
        if (noteToGet) {
            [[OCAPIClient sharedClient] GET:path parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
                //NSLog(@"Note: %@", responseObject);
                NSDictionary *noteDict = (NSDictionary*)responseObject;
                NSLog(@"NoteDict: %@", noteDict);
                if ([noteToGet.myId isEqualToNumber:[noteDict objectForKey:@"id"]]) {
                    if ([noteDict objectForKey:@"modified"] > noteToGet.modified) {
                        noteToGet.title = [noteDict objectForKey:@"title"];
                        noteToGet.content = [noteDict objectForKeyNotNull:@"content" fallback:@""];
                        noteToGet.modified = [noteDict objectForKey:@"modified"];
                    }
                    [self saveContext];
                }
            } failure:^(NSURLSessionDataTask *task, NSError *error) {
                NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
                NSString *message;
                switch (response.statusCode) {
                    case 404:
                        message = @"The note does not exist";
                        break;
                    default:
                        message = [NSString stringWithFormat:@"The server responded '%@' and the error reported was '%@'", [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode], [error localizedDescription]];
                        break;
                }
                
                NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Getting Note", @"Title", message, @"Message", nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
            }];
        }
    } else {
        //offline
    }
}


/*
 Create a note
 
 Creates a new note and returns the note. The title is generated from the first line of the content. If no content is passed, a translated string New note will be returned as title
 
 Status: Implemented
 Method: POST
 Route: /notes
 Parameters:
 
 {
 content: "New content"
 }
 
 Returns:
 
 {
 id: 76,
 content: "",
 modified: 1376753464,
 title: ""
 }
 */

- (void)addNote:(NSString*)content {
    __block Note *newNote = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:self.context];
    newNote.myId = [NSNumber numberWithInt:1000000 - notesToAdd.count];
    newNote.title = @"New note";
    newNote.content = content;
    newNote.modified = [NSNumber numberWithLong:[[NSDate date] timeIntervalSince1970]];
    [self saveContext];
    
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        //online
        NSDictionary *params = @{@"content": newNote.content};
        [[OCAPIClient sharedClient] POST:@"notes" parameters:params success:^(NSURLSessionDataTask *task, id responseObject) {
            //NSLog(@"Note: %@", responseObject);
            [self updateNote:newNote fromDictionary:(NSDictionary*)responseObject];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            NSString *message;
            switch (response.statusCode) {
                default:
                    message = [NSString stringWithFormat:@"The server responded '%@' and the error reported was '%@'", [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode], [error localizedDescription]];
                    break;
            }
            
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Adding Note", @"Title", message, @"Message", nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
            [notesToAdd addObject:newNote.myId];
        }];
        
    } else {
        //offline
        [notesToAdd addObject:newNote.myId];
    }
}

/*
 Update a note
 
 Updates a note with the id noteId. Always update your app with the returned title because the title can be renamed if there are collisions on the server. The title is generated from the first line of the content. If no content is passed, a translated string New note will be returned as title
 
 Status: Implemented
 Method: PUT
 Route: /notes/{noteId}
 Parameters:
 
 {
 content: "New content",
 }
 
 Return codes:
 HTTP 404: If the note does not exist
 Returns:
 
 {
 id: 76,
 content: "New content",
 modified: 1376753464,
 title: "New title"
 }
 */

- (void)updateNote:(Note*)note {
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        //online
        NSDictionary *params = @{@"content": note.content};
        NSString *path = [NSString stringWithFormat:@"notes/%@", [note.myId stringValue]];
        __block Note *noteToUpdate = (Note*)[self.context objectWithID:note.objectID];

        [[OCAPIClient sharedClient] PUT:path parameters:params success:^(NSURLSessionDataTask *task, id responseObject) {
            //NSLog(@"Note: %@", responseObject);
            NSDictionary *noteDict = (NSDictionary*)responseObject;
            if ([noteToUpdate.myId isEqualToNumber:[noteDict objectForKey:@"id"]]) {
                noteToUpdate.title = [noteDict objectForKey:@"title"];
                noteToUpdate.content = [noteDict objectForKeyNotNull:@"content" fallback:@""];;
                noteToUpdate.modified = [noteDict objectForKey:@"modified"];
                [self saveContext];
            }
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            NSString *message;
            switch (response.statusCode) {
                case 404:
                    message = @"The note does not exist";
                    break;
                default:
                    message = [NSString stringWithFormat:@"The server responded '%@' and the error reported was '%@'", [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode], [error localizedDescription]];
                    break;
            }
            
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Updating Note", @"Title", message, @"Message", nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
            noteToUpdate.modified = [NSNumber numberWithLong:[[NSDate date] timeIntervalSince1970]];
            [self saveContext];
        }];
        
    } else {
        //offline
        note.modified = [NSNumber numberWithLong:[[NSDate date] timeIntervalSince1970]];
        [self saveContext];
    }
}

/*
 Delete a note
 
 Deletes a note with the id noteId
 
 Status: Implemented
 Method: DELETE
 Route: /notes/{noteId}
 Parameters: none
 Return codes:
 HTTP 404: If the note does not exist
 Returns: nothing
 */

- (void) deleteNote:(Note *)note {
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        //online
        __block Note *noteToDelete = (Note*)[self.context objectWithID:note.objectID];
        NSString *path = [NSString stringWithFormat:@"notes/%@", [noteToDelete.myId stringValue]];
        [[OCAPIClient sharedClient] DELETE:path parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSLog(@"Success deleting note");
            [self.context deleteObject:noteToDelete];
            [self saveContext];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"Failure to delete note");
            [notesToDelete addObject:noteToDelete.myId];
            [self.context deleteObject:noteToDelete];
            [self saveContext];
            NSString *message = [NSString stringWithFormat:@"The error reported was '%@'", [error localizedDescription]];
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Deleting Note", @"Title", message, @"Message", nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
        }];
    } else {
        //offline
        [notesToDelete addObject:note.myId];
        [self.context deleteObject:note];
        [self saveContext];
    }
}

- (void)addNoteFromDictionary:(NSDictionary*)noteDict {
    Note *newNote = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:self.context];
    [self updateNote:newNote fromDictionary:noteDict];
}

- (void)updateNote:(Note *)note fromDictionary:(NSDictionary*)noteDict {
    Note *noteToUpdate = (Note*)[self.context existingObjectWithID:note.objectID error:nil];
    if (noteToUpdate) {
        noteToUpdate.myId = [noteDict objectForKey:@"id"];
        noteToUpdate.modified = [noteDict objectForKey:@"modified"];
        noteToUpdate.title = [noteDict objectForKey:@"title"];
        noteToUpdate.content = [noteDict objectForKeyNotNull:@"content" fallback:@""];
        [self saveContext];
    }
}

- (void)addNotesToServer:(NSArray*)notesArray {
    __block NSMutableArray *successfulAdditions = [NSMutableArray new];
    __block NSMutableArray *failedAdditions = [NSMutableArray new];
    
    dispatch_group_t group = dispatch_group_create();
    [notesToAdd enumerateObjectsUsingBlock:^(NSNumber *noteId, NSUInteger idx, BOOL *stop) {
        __block Note *note = [self noteWithId:noteId];
        if (note) {
            dispatch_group_enter(group);
            NSDictionary *params = @{@"content": note.content};
            [[OCAPIClient sharedClient] POST:@"notes" parameters:params success:^(NSURLSessionDataTask *task, id responseObject) {
                //NSLog(@"Note: %@", responseObject);
                @synchronized(successfulAdditions) {
                    NSDictionary *noteDict = (NSDictionary*)responseObject;
                    Note *responseNote = [self noteWithId:[noteDict objectForKey:@"id"]];
                    if (responseNote) {
                        responseNote.title = [noteDict objectForKey:@"title"];
                        responseNote.content = [noteDict objectForKeyNotNull:@"content" fallback:@""];
                        responseNote.modified = [noteDict objectForKey:@"modified"];
                        [self.context processPendingChanges];
                    }
                    [successfulAdditions addObject:responseNote.myId];
                }
                dispatch_group_leave(group);
            } failure:^(NSURLSessionDataTask *task, NSError *error) {
                //TODO: Determine what to do with failures.
                NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
                NSString *message;
                switch (response.statusCode) {
                    default:
                        message = [NSString stringWithFormat:@"The server responded '%@' and the error reported was '%@'", [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode], [error localizedDescription]];
                        break;
                }
                
                NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Adding Note", @"Title", message, @"Message", nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
                [failedAdditions addObject:note.myId];
            }];
        }
    }];
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [notesToAdd removeObjectsInArray:successfulAdditions];
        [self saveContext];
    });
}

- (void)deleteNotesFromServer:(NSArray*)notesArray {
    __block NSMutableArray *successfulDeletions = [NSMutableArray new];
    __block NSMutableArray *failedDeletions = [NSMutableArray new];
    
    dispatch_group_t group = dispatch_group_create();
    [notesToDelete enumerateObjectsUsingBlock:^(NSNumber *noteId, NSUInteger idx, BOOL *stop) {
        dispatch_group_enter(group);
        NSString *path = [NSString stringWithFormat:@"notes/%@", [noteId stringValue]];
        [[OCAPIClient sharedClient] DELETE:path parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSLog(@"Success deleting from server");
            @synchronized(successfulDeletions) {
                NSString *successId = [task.originalRequest.URL lastPathComponent];
                [successfulDeletions addObject:[NSNumber numberWithInteger:[successId integerValue]]];
            }
            dispatch_group_leave(group);
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"Failure to delete from server");
            NSString *failedId = [task.originalRequest.URL lastPathComponent];
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            switch (response.statusCode) {
                case 404:
                    NSLog(@"Id %@ no longer exists", failedId);
                    @synchronized(successfulDeletions) {
                        [successfulDeletions addObject:[NSNumber numberWithInteger:[failedId integerValue]]];
                    }
                    break;
                default:
                    NSLog(@"Status code: %ld", (long)response.statusCode);
                    @synchronized(failedDeletions) {
                        [failedDeletions addObject:[NSNumber numberWithInteger:[failedId integerValue]]];
                    }
                    break;
            }

            dispatch_group_leave(group);
        }];
    }];
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [notesToDelete removeObjectsInArray:successfulDeletions];
    });
}

- (NSFetchRequest *)noteRequest {
    if (!noteRequest) {
        noteRequest = [[NSFetchRequest alloc] init];
        [noteRequest setEntity:[NSEntityDescription entityForName:@"Note" inManagedObjectContext:self.context]];
        noteRequest.predicate = nil;
    }
    return noteRequest;
}

@end
