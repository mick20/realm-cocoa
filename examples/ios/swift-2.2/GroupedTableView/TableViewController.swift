////////////////////////////////////////////////////////////////////////////
//
// Copyright 2014 Realm Inc.
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

import UIKit
import RealmSwift

class DemoObject: Object {
    dynamic var title = ""
    dynamic var date = NSDate()
    dynamic var sectionTitle = ""
}

class Cell: UITableViewCell {
    override init(style: UITableViewCellStyle, reuseIdentifier: String!) {
        super.init(style: .Subtitle, reuseIdentifier: reuseIdentifier)
    }

    required init(coder: NSCoder) {
        fatalError("NSCoding not supported")
    }
}

var sectionTitles = ["A", "B", "C"]
var objectsBySection = [Results<DemoObject>]()

class TableViewController: UITableViewController {

    var notificationTokens = [NotificationToken]()
    var realm: Realm!

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        realm = try! Realm()

        for i in 0..<sectionTitles.count {
            let unsortedObjects = realm.objects(DemoObject).filter("sectionTitle == '\(sectionTitles[i])'")
            let sortedObjects = unsortedObjects.sorted("date", ascending: true)
            objectsBySection.append(sortedObjects)

            notificationTokens.append(sortedObjects.addNotificationBlock { [unowned self] (changes: RealmCollectionChange) in
                switch changes {
                case .Initial:
                    // Results are now populated and can be accessed without blocking the UI
                    self.tableView.reloadSections(NSIndexSet(index: i), withRowAnimation: .None)
                    break
                case .Update(_, let deletions, let insertions, let modifications):
                    // Query results have changed, so apply them to the TableView
                    self.tableView.beginUpdates()
                    self.tableView.insertRowsAtIndexPaths(insertions.map { NSIndexPath(forRow: $0, inSection: i) },
                        withRowAnimation: .Automatic)
                    self.tableView.deleteRowsAtIndexPaths(deletions.map { NSIndexPath(forRow: $0, inSection: i) },
                        withRowAnimation: .Automatic)
                    self.tableView.reloadRowsAtIndexPaths(modifications.map { NSIndexPath(forRow: $0, inSection: i) },
                        withRowAnimation: .Automatic)
                    self.tableView.endUpdates()
                    break
                case .Error(let err):
                    // An error occurred while opening the Realm file on the background worker thread
                    fatalError("\(err)")
                    break
                }
            })
        }
    }

    // UI

    func setupUI() {
        tableView.registerClass(Cell.self, forCellReuseIdentifier: "cell")

        self.title = "GroupedTableView"
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "BG Add", style: .Plain,
                                                                target: self, action: #selector(backgroundAdd))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Add,
                                                                 target: self, action: #selector(add))
    }

    // Table view data source

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return sectionTitles.count
    }

    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sectionTitles[section]
    }

    override func tableView(tableView: UITableView?, numberOfRowsInSection section: Int) -> Int {
        return Int(objectsBySection[section].count)
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("cell", forIndexPath: indexPath) as! Cell

        let object = objectForIndexPath(indexPath)
        cell.textLabel?.text = object?.title
        cell.detailTextLabel?.text = object?.date.description

        return cell
    }

    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            try! realm.write {
                self.realm.delete(objectForIndexPath(indexPath)!)
            }
        }
    }

    // Actions

    func backgroundAdd() {
        let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        // Import many items in a background thread
        dispatch_async(queue) {
            // Get new realm and table since we are in a new thread
            let realm = try! Realm()
            realm.beginWrite()
            for _ in 0..<5 {
                // Add row via dictionary. Order is ignored.
                realm.create(DemoObject.self, value: ["title": randomTitle(), "date": NSDate(), "sectionTitle": randomSectionTitle()])
            }
            try! realm.commitWrite()
        }
    }

    func add() {
        try! realm.write {
            let object = [randomTitle(), NSDate(), randomSectionTitle()]
            self.realm.create(DemoObject.self, value: object)
        }
    }
}

// Helpers

func objectForIndexPath(indexPath: NSIndexPath) -> DemoObject? {
    return objectsBySection[indexPath.section][indexPath.row]
}

func randomTitle() -> String {
    return "Title \(arc4random())"
}

func randomSectionTitle() -> String {
    return sectionTitles[Int(rand()) % sectionTitles.count]
}
