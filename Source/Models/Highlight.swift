//
//  Highlight.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 11/08/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import Foundation
import CoreData

@objc(Highlight)
class Highlight: NSManagedObject {

    @NSManaged var bookId: String
    @NSManaged var content: String
    @NSManaged var contentPost: String
    @NSManaged var contentPre: String
    @NSManaged var startPos : NSNumber
    @NSManaged var endPos : NSNumber
    @NSManaged var date: NSDate
    @NSManaged var highlightId: String
    @NSManaged var page: NSNumber
    @NSManaged var type: NSNumber
    @NSManaged var notes: String
    @NSManaged var childCount: NSNumber
}

public typealias Completion = (error: NSError?) -> ()
let coreDataManager = CoreDataManager()

extension Highlight {
    
    static func persistHighlight(object: FRHighlight, completion: Completion?, note : String) {
        var highlight: Highlight?
        
        do {
            let fetchRequest = NSFetchRequest(entityName: "Highlight")
            fetchRequest.predicate = NSPredicate(format:"highlightId = %@", object.id)
            highlight = try coreDataManager.managedObjectContext.executeFetchRequest(fetchRequest).last as? Highlight
        } catch let error as NSError {
            print(error)
            highlight = nil
        }
  
        if highlight != nil {
            highlight!.content = object.content
            highlight!.contentPre = object.contentPre
            highlight!.contentPost = object.contentPost
            highlight!.date = object.date
            highlight!.type = object.type.hashValue
            highlight!.notes = note
            highlight!.startPos = object.startPos
            highlight!.endPos = object.endPos
            highlight!.childCount = object.childCount
        } else {
            highlight = NSEntityDescription.insertNewObjectForEntityForName("Highlight", inManagedObjectContext: coreDataManager.managedObjectContext) as? Highlight
            coreDataManager.saveContext()

            highlight!.bookId = object.bookId
            highlight!.content = object.content
            highlight!.contentPre = object.contentPre
            highlight!.contentPost = object.contentPost
            highlight!.date = NSDate()
            highlight!.highlightId = object.id
            highlight!.page = object.page
            highlight!.type = object.type.hashValue
            highlight!.notes = note
            highlight!.startPos = object.startPos
            highlight!.endPos = object.endPos
            highlight!.childCount = object.childCount
        }
        // Save
        do {
            try coreDataManager.managedObjectContext.save()
            if (completion != nil) {
                completion!(error: nil)
            }
        } catch let error as NSError {
            if (completion != nil) {
                completion!(error: error)
            }
        }
    }

    static func persistHighlight(){
    
        // Save
        do {
            try coreDataManager.managedObjectContext.save()

        } catch let error as NSError {
            print(error)
        }
    
    }
    
    static func getHighlightById(highId : String) -> Highlight? {
        var highlight: Highlight?
        do {
            let fetchRequest = NSFetchRequest(entityName: "Highlight")
            fetchRequest.predicate = NSPredicate(format:"highlightId = %@", highId)
            
            highlight = try coreDataManager.managedObjectContext.executeFetchRequest(fetchRequest).last as? Highlight
            return highlight
        }catch let error as NSError {
            print("Error on remove highlight: \(error)")
        }
        return nil
    }
    
    static func removeById(highlightId: String) {
        var highlight: Highlight?
        
        do {
            let fetchRequest = NSFetchRequest(entityName: "Highlight")
            fetchRequest.predicate = NSPredicate(format:"highlightId = %@", highlightId)
            
            highlight = try coreDataManager.managedObjectContext.executeFetchRequest(fetchRequest).last as? Highlight
            
            if highlight != nil {
                coreDataManager.managedObjectContext.deleteObject(highlight!)
                coreDataManager.saveContext()
            }
        } catch let error as NSError {
            print("------>Error on remove highlight: \(error)")
        }
    }
    
    static func updateById(highlightId: String, type: HighlightStyle) {
        var highlight: Highlight?
        
        do {
            let fetchRequest = NSFetchRequest(entityName: "Highlight")
            fetchRequest.predicate = NSPredicate(format:"highlightId = %@", highlightId)
            
            highlight = try coreDataManager.managedObjectContext.executeFetchRequest(fetchRequest).last as? Highlight
            
            let replaced = "class=\"\(HighlightStyle.classForStyle(highlight!.type.hashValue))\""
            let replace = "class=\"\(HighlightStyle.classForStyle(type.hashValue))\""
            var content = highlight!.content
            content = content.stringByReplacingOccurrencesOfString(replaced, withString: replace)
            highlight?.content = content
            highlight?.type = type.hashValue
            coreDataManager.saveContext()
        } catch let error as NSError {
            print("Error on update highlight: \(error)")
        }
    }
    
    static func allByBookId(bookId: String, andPage page: NSNumber? = nil) -> [Highlight] {
        var highlights: [Highlight]?
        let predicate = (page != nil) ? NSPredicate(format: "bookId = %@ && page = %@", bookId, page!) : NSPredicate(format: "bookId = %@", bookId)
        
        do {
            let fetchRequest = NSFetchRequest(entityName: "Highlight")
            let sorter: NSSortDescriptor = NSSortDescriptor(key: "date" , ascending: false)
            fetchRequest.predicate = predicate
            fetchRequest.sortDescriptors = [sorter]
            
            highlights = try coreDataManager.managedObjectContext.executeFetchRequest(fetchRequest) as? [Highlight]
            return highlights!
        } catch {
            return [Highlight]()
        }
    }
}